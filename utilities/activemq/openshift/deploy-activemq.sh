#!/bin/bash

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $AMQ_IMAGE ]]; then ENV_VAR_NOT_SET="AMQ_IMAGE"; fi
if [[ -z $SC_NAME ]]; then ENV_VAR_NOT_SET="SC_NAME"; fi
if [[ -z $AMQ_NAMESPACE ]]; then ENV_VAR_NOT_SET="AMQ_NAMESPACE"; fi
if [[ -z $ACR_NAME ]]; then ENV_VAR_NOT_SET="ACR_NAME"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $CLIENT_ID ]]; then ENV_VAR_NOT_SET="CLIENT_ID"; fi
if [[ -z $CLIENT_SECRET ]]; then ENV_VAR_NOT_SET="CLIENT_SECRET"; fi
if [[ -z $TENANT_ID ]]; then ENV_VAR_NOT_SET="TENANT_ID"; fi
if [[ -z $SUBSCRIPTION_ID ]]; then ENV_VAR_NOT_SET="SUBSCRIPTION_ID"; fi
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $ADMIN_PASSWORD ]]; then ENV_VAR_NOT_SET="ADMIN_PASSWORD"; fi

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
# Create namespace
if [[ -z $(${BIN_DIR}/oc get namespaces | grep ${AMQ_NAMESPACE}) ]]; then 
    echo "Creating Active MQ Namespace"
    cat << EOF >> ${WORKSPACE_DIR}/amq-namespace.yaml
kind: Namespace
apiVersion: v1
metadata:
  name: $AMQ_NAMESPACE
  labels:
    name: active-mq
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/amq-namespace.yaml
else
    echo "Using existing active mq namespace"
fi

######
# Create service account and assign permissions
if [[ -z $(${BIN_DIR}/oc get serviceaccounts -n ${AMQ_NAMESPACE} | grep runasanyuid) ]]; then
    echo "Creating service account"
    ${BIN_DIR}/oc create serviceaccount runasanyuid -n ${AMQ_NAMESPACE}
    ${BIN_DIR}/oc adm policy add-scc-to-user anyuid -z runasanyuid --as system:admin -n ${AMQ_NAMESPACE}
else
    echo "Using existing service account"
fi

######
# Create Azure Container Registry secret
if [[ -z $(${BIN_DIR}/oc get secrets -n ${AMQ_NAMESPACE} | grep azure-acr-credentials) ]]; then
    echo "Creating Azure container registry secret"
    ${BIN_DIR}/oc create secret docker-registry azure-acr-credentials --docker-server=$ACR_NAME.azurecr.io --docker-username=$CLIENT_ID --docker-password=$CLIENT_SECRET -n $AMQ_NAMESPACE
else
    echo "Using existing container registry secret"
fi

######
# Create Active MQ credentials secret
if [[ -z $(${BIN_DIR}/oc get secrets -n ${AMQ_NAMESPACE} | grep active-mq-credentials) ]]; then
    echo "Creating Active MQ credentials secret"
    touch ${WORKSPACE_DIR}/jetty-realm.properties
    echo "admin: ${ADMIN_PASSWORD}, admin" >> ${WORKSPACE_DIR}/jetty-realm.properties
    echo "guest: ${ADMIN_PASSWORD}, user" >> ${WORKSPACE_DIR}/jetty-realm.properties
    ${BIN_DIR}/oc create secret generic active-mq-credentials --from-file=${WORKSPACE_DIR}/jetty-realm.properties -n ${AMQ_NAMESPACE}
else
    echo "Using existing active mq secrets"
fi

######
# Create Active MQ PVC
if [[ -z $(${BIN_DIR}/oc get pvc -n ${AMQ_NAMESPACE} | grep active-mq-storage) ]]; then
    echo "Creating Active MQ Persistent Volume Claim"
    cat << EOF >> ${WORKSPACE_DIR}/amq-pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: active-mq-storage
  namespace: $AMQ_NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 20Gi
  storageClassName: $SC_NAME
  volumeMode: Filesystem
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/amq-pvc.yaml
else
    echo "Using existing Active MQ PVC"
fi

#######
# Create Active MQ Deployment
if [[ -z $(${BIN_DIR}/oc get deployments -n active-mq | grep active-mq) ]]; then
    echo "Creating Active MQ Deployment with image ${AMQ_IMAGE}"
    cat << EOF >> ${WORKSPACE_DIR}/amq-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: active-mq
  namespace: $AMQ_NAMESPACE
labels:
   app: active-mq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: active-mq
  template:
    metadata:
      labels:
          app: active-mq
    spec:
      serviceAccountName: runasanyuid
      securityContext:
        runAsUser: 100
      imagePullSecrets: 
         - name: azure-acr-credentials
      containers:
          - name: active-mq
            image: $AMQ_IMAGE
            env:
              - name: ACTIVEMQ_TMP
                value : "/tmp"
            imagePullPolicy: Always
            resources:
               requests:
                  memory: 500Mi
                  cpu: 200m
               limits:
                  memory: 1000Mi
                  cpu: 400m
            volumeMounts:
            - name: active-creds
              mountPath: /opt/apache/apache-activemq-5.17.1/conf/jetty-realm.properties
              subPath: jetty-realm.properties
            - name: active-storage
              mountPath: /opt/apache/apache-activemq-5.17.1/data
      volumes:
      - name: active-creds
        secret:
          secretName: active-mq-credentials
      - name: active-storage
        persistentVolumeClaim:
          claimName: active-mq-storage
      restartPolicy: Always
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/amq-deployment.yaml
else
    echo "Using existing Active MQ deployment"
fi

######
# Create Active MQ service
if [[ -z $(${BIN_DIR}/oc get services -n ${AMQ_NAMESPACE} | grep active-mq | grep ClusterIP ) ]]; then
    echo "Creating Active MQ Service"
    cat << EOF >> ${WORKSPACE_DIR}/amq-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: active-mq
  namespace: $AMQ_NAMESPACE
  labels:
    app: active-mq
spec:
  selector:
    app: active-mq
  ports:
  - name: dashboard
    port: 8161
    targetPort: 8161
    protocol: TCP
  - name: openwire
    port: 61616
    targetPort: 61616
    protocol: TCP
  - name: amqp
    port: 5672
    targetPort: 5672
    protocol: TCP
  - name: stomp
    port: 61613
    targetPort: 61613
    protocol: TCP
  - name: mqtt
    port: 1883
    targetPort: 1883
    protocol: TCP
  type: ClusterIP
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/amq-service.yaml
else
    echo "Using existing Active MQ service"
fi

######
# Create route
export DOMAIN=$(az aro show  -n $ARO_CLUSTER -g $RESOURCE_GROUP --query "clusterProfile.domain" -o tsv)
export LOCATION=$(az aro show  -n $ARO_CLUSTER -g $RESOURCE_GROUP --query "location" -o tsv)
if [[ -z $(${BIN_DIR}/oc get routes -n ${AMQ_NAMESPACE} | grep amq | grep openwire) ]]; then
    echo "Creating Active MQ route"
    cat << EOF >> amq-route.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: amq
  namespace: $AMQ_NAMESPACE
spec:
  host: active-mq.apps.$DOMAIN.$LOCATION.aroapp.io
  to:
    kind: Service
    name: active-mq
    weight: 100
  port:
    targetPort: openwire
  wildcardPolicy: None
EOF
    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/amq-route.yaml
else
    echo "Using existing Active MQ route"
fi

######
# Create route dashboard
if [[ -z $(${BIN_DIR}/oc get routes -n ${AMQ_NAMESPACE} | grep amq-dash | grep dashboard) ]]; then
    echo "Creating route dashboard"
    cat << EOF >> ${WORKSPACE_DIR}/amq-route-dashboard.yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: amq-dash
  namespace: $AMQ_NAMESPACE
spec:
  host: amq-dash-active-mq.apps.$DOMAIN.$LOCATION.aroapp.io
  to:
    kind: Service
    name: active-mq
    weight: 100
  port:
    targetPort: dashboard
  wildcardPolicy: None
EOF
${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/amq-route-dashboard.yaml
else
    echo "Using existing route dashboard"
fi