#!/bin/bash

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $CLIENT_ID ]]; then ENV_VAR_NOT_SET="CLIENT_ID"; fi
if [[ -z $CLIENT_SECRET ]]; then ENV_VAR_NOT_SET="CLIENT_SECRET"; fi
if [[ -z $TENANT_ID ]]; then ENV_VAR_NOT_SET="TENANT_ID"; fi
if [[ -z $SUBSCRIPTION_ID ]]; then ENV_VAR_NOT_SET="SUBSCRIPTION_ID"; fi
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $OMS_NAMESPACE ]]; then ENV_VAR_NOT_SET="OMS_NAMESPACE"; fi
if [[ -z $ADMIN_PASSWORD ]]; then ENV_VAR_NOT_SET="ADMIN_PASSWORD"; fi
if [[ -z $WHICH_OMS ]]; then ENV_VAR_NOT_SET="WHICH_OMS"; fi
if [[ -z $ACR_NAME ]]; then ENV_VAR_NOT_SET="ACR_NAME"; fi
if [[ -z $STORAGE_ACCOUNT_NAME ]]; then ENV_VAR_NOT_SET="STORAGE_ACCOUNT_NAME"; fi
if [[ -z $FILE_TYPE ]]; then ENV_VAR_NOT_SET="FILE_TYPE"; fi
if [[ -z $SC_NAME ]]; then ENV_VAR_NOT_SET="SC_NAME"; fi
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then ENV_VAR_NOT_SET="IBM_ENTITLEMENT_KEY"; fi
if [[ -z $PSQL_HOST ]]; then ENV_VAR_NOT_SET="PSQL_HOST"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

# Setup workspace
if [[ -z $WORKSPACE_DIR ]]; then
    WORKSPACE_DIR="/workspace"
fi
mkdir -p $WORKSPACE_DIR

# Setup binary directory
if [[ -z $BIN_DIR ]]; then
    BIN_DIR="/usr/local/bin"
fi

# Setup temporary directory
if [[ -z $TMP_DIR ]]; then
    TMP_DIR="${WORKSPACE_DIR}/tmp"
fi
mkdir -p $TMP_DIR

#######
# Set defaults (can be overriden with environment variables)
if [[ -z $PSQL_POD_NAME ]]; then export PSQL_POD_NAME="psql-client"; fi
if [[ -z $DB_NAME ]]; then export DB_NAME="oms"; fi
if [[ -z $SCHEMA_NAME ]]; then export SCHEMA_NAME="oms"; fi
if [[ -z $OM_INSTANCE_NAME ]]; then export OM_INSTANCE_NAME="oms-instance"; fi

#####
# Download OC and kubectl
ARCH=$(uname -m)
OC_FILETYPE="linux"
KUBECTL_FILETYPE="linux"

OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/stable/openshift-client-${OC_FILETYPE}.tar.gz"
#KUBECTL_URL="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/${KUBECTL_FILETYPE}/${ARCH}/kubectl"

# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    echo "Downloading and installing oc and kubectl"
    curl -sLo $TMP_DIR/openshift-client.tgz $OC_URL

    if ! tar tzf $TMP_DIR/openshift-client.tgz 1> /dev/null 2> /dev/null; then
        echo "ERROR: Tar file from $OC_URL is corrupted"
        exit 1
    fi

    tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc kubectl

    mv ${TMP_DIR}/oc ${BIN_DIR}/oc
    mv ${TMP_DIR}/kubectl ${BIN_DIR}/kubectl
fi

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" -t "$TENANT_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        echo "ERROR: Unable to login to service principal. Check supplied details in credentials.properties."
        exit 1
    else
        echo "Successfully logged on with service principal"
    fi
    az account set --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        echo "ERROR: Unable to use subscription id $SUBSCRIPTION_ID. Please check and try agian."
        exit 1
    else
        echo "Successfully changed to subscription : $(az account show --query name -o tsv)"
    fi
else
    echo "Using existing Azure CLI login"
fi

#######
# Login to cluster

if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
    API_SERVER=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query apiserverProfile.url -o tsv | sed -e 's#^https://##; s#/##')
    CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
    ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD
else   
    CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')
    API_SERVER=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query apiserverProfile.url -o tsv | sed -e 's#^https://##; s#/##')
    if [[ $CURRENT_SERVER == $API_SERVER ]]; then
        echo "Already logged into cluster"
    else
        CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
        ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD
    fi
fi

######
# Wait for cluster operators to finish deploying

######
# Create required namespace
CURRENT_NAMESPACE=$(${BIN_DIR}/oc get namespaces | grep $OMS_NAMESPACE)
if [[ -z $CURRENT_NAMESPACE ]]; then
    echo "Creating namespace"
    ${BIN_DIR}/oc create namespace $OMS_NAMESPACE
else
    echo "Namespace $OMS_NAMESPACE already exists"
fi

######
# Install and configure Azure Files CSI Drivers and Storage Classes
echo "Creating Azure files storage"

export LOCATION=$(az group show --resource-group $RESOURCE_GROUP --query location -o tsv)
export RESOURCE_GROUP_NAME=$RESOURCE_GROUP

#####
# Set ARO cluster permissions
if [[ $(${BIN_DIR}/oc get clusterrole | grep azure-secret-reader) ]]; then
    echo "Using existing cluster role"
else
    oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets
    oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder
fi

#####
# Create storage class
if [[ -z $(${BIN_DIR}/oc get sc | grep $SC_NAME) ]]; then
    echo "Creating Azure file storage"
    cat << EOF >> ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: $SC_NAME
provisioner: kubernetes.io/azure-file
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - actimeo=30
  - noperm
parameters:
  location: $LOCATION
  secretNamespace: kube-system
  skuName: $FILE_TYPE
  storageAccount: $STORAGE_ACCOUNT_NAME
  resourceGroup: $RESOURCE_GROUP
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

oc create -f ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
else
    echo "Azure file storage already exists"
fi


######
# Install and configure IBM Operator catalog
export CONSOLEADMINPW="$ADMIN_PASSWORD"
export CONSOLENONADMINPW="$ADMIN_PASSWORD"
export DBPASSWORD="$ADMIN_PASSWORD"
export TLSSTOREPW="$ADMIN_PASSWORD"
export TRUSTSTOREPW="$ADMIN_PASSWORD"
export KEYSTOREPW="$ADMIN_PASSWORD"

if [[ -z $(${BIN_DIR}/oc get rolebindings -n $OMS_NAMESPACE | grep oms-rolebinding) ]]; then
    echo "Creating OMS RBAC"
cat << EOF >> ${WORKSPACE_DIR}/oms-rbac.yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: oms-role
  namespace: $OMS_NAMESPACE
rules:
  - apiGroups: ['']
    resources: ['secrets']
    verbs: ['get', 'watch', 'list', 'create', 'delete', 'patch', 'update']

---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: oms-rolebinding
  namespace: $OMS_NAMESPACE
subjects:
  - kind: ServiceAccount
    name: default
    namespace: $OMS_NAMESPACE
roleRef:
  kind: Role
  name: oms-role
  apiGroup: rbac.authorization.k8s.io
EOF

    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-rbac.yaml
else
    echo "OMS RBAC already exists"
fi

if [[ -z $(${BIN_DIR}/oc get secrets -n $OMS_NAMESPACE | grep oms-secret) ]]; then
cat << EOF >> ${WORKSPACE_DIR}/oms-secret.yaml
apiVersion: v1
kind: Secret
metadata:
   name: oms-secret
   namespace: $OMS_NAMESPACE
type: Opaque
stringData:
  consoleAdminPassword: $CONSOLEADMINPW
  consoleNonAdminPassword: $CONSOLENONADMINPW
  dbPassword: $DBPASSWORD
  tlskeystorepassword: $TLSSTOREPW
  trustStorePassword: $TRUSTSTOREPW
  keyStorePassword: $KEYSTOREPW
EOF
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-secret.yaml
else
    echo "OMS Secret already exists"
fi

# Get Azure container registry credentials
if [[ -z $(${BIN_DIR}/oc get secrets --all-namespaces | grep $ACR_NAME-dockercfg ) ]]; then
    echo "Creating ACR Login Secret"
    export ACR_LOGIN_SERVER=$(az acr show -n $ACR_NAME -g $RESOURCE_GROUP --query loginServer -o tsv)
    export ACR_PASSWORD=$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query passwords[0].value -o tsv )
cat << EOF >> ${WORKSPACE_DIR}/oms-pullsecret.json
{
    "auths":{
        "$ACR_LOGIN_SERVER":{
            "auth":"$ACR_PASSWORD"
        }
    }
}
EOF
    ${BIN_DIR}/oc create secret generic $ACR_NAME-dockercfg --from-file=.dockercfg=${WORKSPACE_DIR}/oms-pullsecret.json --type=kubernetes.io/dockercfg 
else
    echo "ACR login secret already created on cluster"
fi


#######
# Create entitlement key secret for image pull
if [[ -z $(${BIN_DIR}/oc get secret -n ${OMS_NAMESPACE} | grep ibm-entitlement-key) ]]; then
    echo "Creating entitlement key secret"
    ${BIN_DIR}/oc create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $OMS_NAMESPACE
else
    echo "Using existing entitlement key secret"
fi

########
# Install OMS Operator

export OMS_VERSION=$WHICH_OMS

if [[ ${WHICH_OMS} == *"-pro-"* ]]; then
    export OPERATOR_NAME="ibm-oms-pro"
    export OPERATOR_CSV="ibm-oms-pro.v1.0"
else
    export OPERATOR_NAME="ibm-oms-ent"
    export OPERATOR_CSV="ibm-oms-ent.v1.0"
fi

if [[ -z $(${BIN_DIR}/oc get operators -n $OMS_NAMESPACE | grep ibm-oms) ]]; then
    echo "Installing OMS Operator"
    echo "Name        : $OPERATOR_NAME"
    echo "Operator CSV: $OPERATOR_CSV"
cat << EOF >> ${WORKSPACE_DIR}/install-oms-operator.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: oms-operator-global
  namespace: $OMS_NAMESPACE
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-sterling-oms
  namespace: openshift-marketplace
spec:
  displayName: IBM Sterling OMS
  image: $OMS_VERSION
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 10m0s
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: oms-operator
  namespace: $OMS_NAMESPACE
spec:
  channel: v1.0
  installPlanApproval: Automatic
  name: $OPERATOR_NAME
  source: ibm-sterling-oms
  sourceNamespace: openshift-marketplace
EOF
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/install-oms-operator.yaml
else
    echo "IBM OMS Operator already installed"
fi

#######
# Create OMS Persistent Volume
if [[ -z $(${BIN_DIR}/oc get pvc -n $OMS_NAMESPACE | grep oms-pv) ]]; then
    echo "Creating PVC for OMS"
cat << EOF >> ${WORKSPACE_DIR}/oms-pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: oms-pvc
  namespace: $OMS_NAMESPACE             
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: $SC_NAME
  volumeMode: Filesystem
EOF

    oc create -f ${WORKSPACE_DIR}/oms-pvc.yaml
else
    echo "PVC for OMS already exists"
fi


#######
# Wait for operator to finish installing
while [[ $(${BIN_DIR}/oc get pods -n ${OMS_NAMESPACE} | grep ibm-oms-controller-manager | awk '{print $2}') != '3/3' ]] && [[ $count < 60 ]]; do
    sleep 30
    echo "Waiting for IBM OMS operator to install $count"
    count=$(( $count + 1 ))
done

# Check operator status
if [[ $(${BIN_DIR}/oc get pods -n ${OMS_NAMESPACE} | grep ibm-oms-controller-manager | awk '{print $2}') != '3/3' ]]; then
    echo "ERROR: IBM OMS Operator did not start before timeout"
    exit 1;
else
    echo "IBM OMS Operator installed and running"
fi

######
# Create psql pod to manage DB (this will be used to create db and schema)
if [[ -z $(${BIN_DIR}/oc get pods -n ${OMS_NAMESPACE} | grep ${PSQL_POD_NAME}) ]]; then
    echo "Creating new psql client pod ${PSQL_POD_NAME}"
    cat << EOF >> ${WORKSPACE_DIR}/psql-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ${PSQL_POD_NAME}
  namespace: ${OMS_NAMESPACE}
spec:
  containers:
    - name: psql-container
      image: rhel8/postgresql-12
      command: [ "/bin/bash", "-c", "--" ]
      args: [ "while true; do sleep 30; done;" ]
      env:
        - name: PSQL_HOST
          value: ${PSQL_HOST}
        - name: PSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: oms-secret
              key: dbPassword
        - name: DB_NAME
          value: ${DB_NAME}
        - name: SCHEMA_NAME
          value: ${SCHEMA_NAME}
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/psql-pod.yaml
else
    echo "Using existing psql client pod ${PSQL_POD_NAME}"
fi

######
# Create database and schema in db server


#######
# Create OMSEnvironment
if [[ -z $(${BIN_DIR}/oc get omenvironment.apps.oms.ibm.com -n ${OMS_NAMESPACE} | grep ${OM_INSTANCE_NAME}) ]]; then
    echo "Creating new OMEnvironment instance ${OM_INSTANCE_NAME}"
    export ARO_INGRESS=$(az aro show -g $RESOURCE_GROUP -n $ARO_CLUSTER --query consoleProfile.url -o tsv | sed -e 's#^https://console-openshift-console.##; s#/##')
    cat << EOF >> omenvironment.yaml
apiVersion: apps.oms.ibm.com/v1beta1
kind: OMEnvironment
metadata:
  name: ${OM_INSTANCE_NAME}
  namespace: ${OMS_NAMESPACE}
  annotations:
    apps.oms.ibm.com/dbvendor-install-driver: "true"
    apps.oms.ibm.com/dbvendor-auto-transform: "true"
    apps.oms.ibm.com/dbvendor-driver-url: "https://jdbc.postgresql.org/download/postgresql-42.2.27.jre7.jar"
spec:
  license:
    accept: true
    acceptCallCenterStore: true
  common:
    ingress:
      host: "${ARO_INGRESS}"
      ssl:
        enabled: false
  database:
    postgresql:
      dataSourceName: jdbc/OMDS
      host: "${PSQL_HOST}"
      name: ${DB_NAME}
      port: 5432
      schema: ${SCHEMA_NAME}
      secure: true
      user: azureuser
  dataManagement:
    mode: create
  storage:
    name: oms-pvc
  secret: oms-secret
  healthMonitor:
    profile: ProfileSmall
    replicaCount: 1
  orderHub:
    bindingAppServerName: smcfs
    base:
      profile: ProfileSmall
      replicaCount: 1
    extn:
      profile: ProfileSmall
      replicaCount: 1
  image:
    oms:
      tag: 10.0.2209.1-amd64
      repository: cp.icr.io/cp/ibm-oms-professional
    orderHub:
      base:
        tag: 10.0.2209.1-amd64
        repository: cp.icr.io/cp/ibm-oms-professional
      extn:
        tag: 10.0.2209.1-amd64
        repository: cp.icr.io/cp/ibm-oms-professional
    imagePullSecrets:
      - name: ibm-entitlement-key
  networkPolicy:
    ingress: []
    podSelector:
      matchLabels:
        release: oms
        role: appserver
    policyTypes:
      - Ingress
  serverProfiles:
    - name: ProfileSmall
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 200m
          memory: 512Mi
    - name: ProfileMedium
      resources:
        limits:
          cpu: 2000m
          memory: 2Gi
        requests:
          cpu: 500m
          memory: 1Gi
    - name: ProfileLarge
      resources:
        limits:
          cpu: 4000m
          memory: 4Gi
        requests:
          cpu: 500m
          memory: 2Gi
    - name: ProfileHuge
      resources:
        limits:
          cpu: 4000m
          memory: 8Gi
        requests:
          cpu: 500m
          memory: 4Gi
    - name: ProfileColossal
      resources:
        limits:
          cpu: 4000m
          memory: 16Gi
        requests:
          cpu: 500m
          memory: 4Gi
  servers:
    - name: smcfs
      replicaCount: 1
      profile: ProfileHuge
      appServer:
        dataSource:
          minPoolSize: 10
          maxPoolSize: 25
        ingress:
          contextRoots: [smcfs, sbc, sma, isccs, wsc, isf]
        threads:
          min: 10
          max: 25
        vendor: websphere
  serviceAccount: default
  upgradeStrategy: RollingUpdate
  customerOverrides:
      - groupName: BaseProperties
        propertyList:
          yfs.yfs.ssi.enabled: N
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/omenvironment.yaml
else
    echo "Using existing OMEnvironment instance ${OM_INSTANCE_NAME}"
fi

