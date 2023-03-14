#!/bin/bash

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $BRANCH_NAME ]]; then ENV_VAR_NOT_SET="BRANCH_NAME"; fi
if [[ -z $CLIENT_ID ]]; then ENV_VAR_NOT_SET="CLIENT_ID"; fi
if [[ -z $CLIENT_SECRET ]]; then ENV_VAR_NOT_SET="CLIENT_SECRET"; fi
if [[ -z $TENANT_ID ]]; then ENV_VAR_NOT_SET="TENANT_ID"; fi
if [[ -z $SUBSCRIPTION_ID ]]; then ENV_VAR_NOT_SET="SUBSCRIPTION_ID"; fi
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $OMS_NAMESPACE ]]; then ENV_VAR_NOT_SET="OMS_NAMESPACE"; fi
if [[ -z $VNET_NAME ]]; then ENV_VAR_NOT_SET="VNET_NAME"; fi
if [[ -z $SUBNET_PRIVATE_ENDPOINT_NAME ]]; then ENV_VAR_NOT_SET="SUBNET_PRIVATE_ENDPOINT_NAME"; fi
if [[ -z $ADMIN_PASSWORD ]]; then ENV_VAR_NOT_SET="ADMIN_PASSWORD"; fi
if [[ -z $WHICH_OMS ]]; then ENV_VAR_NOT_SET="WHICH_OMS"; fi
if [[ -z $ACR_NAME ]]; then ENV_VAR_NOT_SET="ACR_NAME"; fi
if [[ -z $STORAGE_ACCOUNT_NAME ]]; then ENV_VAR_NOT_SET="STORAGE_ACCOUNT_NAME"; fi
if [[ -z $FILE_TYPE ]]; then ENV_VAR_NOT_SET="FILE_TYPE"; fi
if [[ -z $SC_NAME ]]; then ENV_VAR_NOT_SET="SC_NAME"; fi
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then ENV_VAR_NOT_SET="IBM_ENTITLEMENT_KEY"; fi

if [[ -n $ENV_VAR_NOT_SET ]]; then
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

# Setup workspace
WORKSPACE_DIR="/workspace"
mkdir -p $WORKSPACE_DIR

# Setup binary directory
BIN_DIR="/usr/local/bin"

# Setup temporary directory
TMP_DIR="${WORKSPACE_DIR}/tmp"
mkdir -p $TMP_DIR

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
# Download and install envsubst
if [[ ! -f ${BIN_DIR}/envsubst ]]; then
    echo "Downloading and installing envsubst"
    ENV_SUB_VERSION="v1.4.2"
    ENV_SUB_ARCH=$(uname -m)
    ENV_SUB_OS=$(uname -s)
    ENV_SUB_URL="https://github.com/a8m/envsubst/releases/download/${ENV_SUB_VERSION}/envsubst-${ENV_SUB_OS}-${ENV_SUB_ARCH}"
    curl -sLo ${TMP_DIR}/envsubst ${ENV_SUB_URL}
    chmod +x ${TMP_DIR}/envsubst
    mv ${TMP_DIR}/envsubst /usr/local/bin/envsubst
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
oc create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $OMS_NAMESPACE

########
# Install OMS Operator

export OMS_VERSION=$WHICH_OMS

if [[ ${WHICH_OMS} == *"-pro-"* ]]; then
    export OPERATOR_NAME="ibm-oms-pro"
    export OPERATOR_CSV="ibm-oms-pro.v1.0.0"
else
    export OPERATOR_NAME="ibm-oms-ent"
    export OPERATOR_CSV="ibm-oms-ent.v1.0.0"
fi

if [[ -z $(${BIN_DIR}/oc get operators -n $OMS_NAMESPACE | grep ibm-oms) ]]; then
    echo "Installing OMS Operator"
    echo "Name        : $OPERATOR_NAME"
    echo "Operator CSV: $OPERATOR_CSV"
cat << EOF >> ${WORKSPACE_DIR}/install-oms-operator.yaml
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
  channel: "v1.0.1"
  installPlanApproval: Automatic
  name: $OPERATOR_NAME
  source: ibm-sterling-oms
  sourceNamespace: openshift-marketplace
  startingCSV: $OPERATOR_CSV
EOF
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/install-oms-operator.yaml
else
    echo "IBM OMS Operator already installed"
fi

#######
# Create OMS Persistent Volume
if [[ -z $(${BIN_DIR}/oc get pvc -n $OMS_NAMESPACE | grep oms-pv) ]]; then
    echo "Creating PVC for OMS"
cat << EOF >> ${WORKSPACE_DIR}/azure-storageclass-file.yaml
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

    oc create -f ${WORKSPACE_DIR}/azure-storageclass-file.yaml
else
    echo "PVC for OMS already exists"
fi


#######
# Create JMS Config Map


#######
# Create OMSEnvironment

