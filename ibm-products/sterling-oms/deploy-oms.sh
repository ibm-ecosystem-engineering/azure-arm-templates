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

if [[ -n $ENV_VAR_NOT_SET ]]; then
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

export LOCATION=$(az group show --resource-group $RESOURCE_GROUP --query location -o tsv)
export RESOURCE_GROUP_NAME=$RESOURCE_GROUP

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
echo "==== START AZURE FILES CONFIGURATION ===="

# Below not required as already setup with ARO
# curl -sLo ${TMP_DIR}/azure.json https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/azure-file-storage/azure.json
# envsubst < ${TMP_DIR}/azure.json > ${WORKSPACE_DIR}/azure-updated.json
# export AZURE_CLOUD_SECRET=$(cat ${WORKSPACE_DIR}/azure-updated.json | base64 | awk '{printf $0}' ; echo)
# curl -sLo ${TMP_DIR}/azure-cloud-provider.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/azure-file-storage/azure-cloud-provider.yaml
# envsubst < ${TMP_DIR}/azure-cloud-provider.yaml > ${WORKSPACE_DIR}/azure-cloud-provider-updated.yaml
# oc apply -f ${WORKSPACE_DIR}/azure-cloud-provider-updated.yaml


# Grant access
${BIN_DIR}/oc adm policy add-scc-to-user privileged system:serviceaccount:kube-system:csi-azurefile-node-sa

# Install CSI Driver
if [[ -z $(${BIN_DIR}/oc get configmaps -n kube-system | grep azure-cred-file) ]]; then
    echo "Installing CSI driver for Azure fileshares"
    ${BIN_DIR}/oc create configmap azure-cred-file --from-literal=path="/etc/kubernetes/cloud.conf" -n kube-system
    export DRIVER_VERSION="v1.18.0"
    echo "Driver version ${DRIVER_VERSION}"
    curl -skSL https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/$DRIVER_VERSION/deploy/install-driver.sh | bash -s $DRIVER_VERSION --
else
    echo "Using existing CSI driver for Azure fileshares"
fi


# Configure standard file storage
if [[ -z $(${BIN_DIR}/oc get sc | grep azurefiles-standard) ]]; then
    curl -sLo ${TMP_DIR}/azurefiles-standard.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/azure-file-storage/azurefiles-standard.yaml
    ${BIN_DIR}/envsubst < ${TMP_DIR}/azurefiles-standard.yaml > ${WORKSPACE_DIR}/azurefiles-standard-updated.yaml
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/azurefiles-standard-updated.yaml
else
    echo "Using existing storage class for Azure standard files"
fi

# Configure premium file storage
if [[ -z $(${BIN_DIR}/oc get sc | grep azurefiles-premium) ]]; then
    curl -sLo ${TMP_DIR}/azurefiles-premium.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/azure-file-storage/azurefiles-premium.yaml
    ${BIN_DIR}/envsubst < ${TMP_DIR}/azurefiles-premium.yaml > ${WORKSPACE_DIR}/azurefiles-premium-updated.yaml
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/azurefiles-premium-updated.yaml
else
    echo "Using existing storage class for Azure premium files"
fi

# Deploy volume binder
${BIN_DIR}/oc apply -f https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/azure-file-storage/persistent-volume-binder.yaml


######
# Install and configure IBM Operator catalog
export CONSOLEADMINPW="$ADMIN_PASSWORD"
export CONSOLENONADMINPW="$ADMIN_PASSWORD"
export DBPASSWORD="$ADMIN_PASSWORD"
export TLSSTOREPW="$ADMIN_PASSWORD"
export TRUSTSTOREPW="$ADMIN_PASSWORD"
export KEYSTOREPW="$ADMIN_PASSWORD"

if [[ -z $(${BIN_DIR}/oc get pvc -n $OMS_NAMESPACE | grep oms-pv) ]]; then
    echo "Creating PVC for OMS"
    curl -sLo ${TMP_DIR}/oms-pvc.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/oms/oms-pvc.yaml
    ${BIN_DIR}/envsubst < ${TMP_DIR}/oms-pvc.yaml > ${WORKSPACE_DIR}/oms-pvc-updated.yaml
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-pvc-updated.yaml
else
    echo "PVC for OMS already exists"
fi

if [[ -z $(${BIN_DIR}/oc get rolebindings -n $OMS_NAMESPACE | grep oms-rolebinding) ]]; then
    echo "Creating OMS RBAC"
    curl -sLo ${TMP_DIR}/oms-rbac.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/oms/oms-rbac.yaml
    ${BIN_DIR}/envsubst < ${TMP_DIR}/oms-rbac.yaml > ${WORKSPACE_DIR}/oms-rbac-updated.yaml
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-rbac-updated.yaml
else
    echo "OMS RBAC already exists"
fi

if [[ -z $(${BIN_DIR}/oc get secrets -n $OMS_NAMESPACE | grep oms-secret) ]]; then
    curl -sLo ${TMP_DIR}/oms-secret.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/oms/oms-secret.yaml
    ${BIN_DIR}/envsubst < ${TMP_DIR}/oms-secret.yaml > ${WORKSPACE_DIR}/oms-secret-updated.yaml
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/oms-secret-updated.yaml
else
    echo "OMS Secret already exists"
fi

# Get Azure container registry credentials
if [[ -z $(${BIN_DIR}/oc get secrets --all-namespaces | grep $ACR_NAME-dockercfg ) ]]; then
    echo "Creating ACR Login Secret"
    export ACR_LOGIN_SERVER=$(az acr show -n $ACR_NAME -g $RESOURCE_GROUP --query loginServer -o tsv)
    export ACR_PASSWORD=$(az acr credential show -n $ACR_NAME -g $RESOURCE_GROUP --query passwords[0].value -o tsv )
    curl -sLo ${TMP_DIR}/oms-pullsecret.json https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/oms/oms-pullsecret.json
    ${BIN_DIR}/envsubst < ${TMP_DIR}/oms-pullsecret.json > ${WORKSPACE_DIR}/oms-pullsecret-updated.json
    ${BIN_DIR}/oc create secret generic $ACR_NAME-dockercfg --from-file=.dockercfg=${WORKSPACE_DIR}/oms-pullsecret-updated.json --type=kubernetes.io/dockercfg 
else
    echo "ACR login secret already created on cluster"
fi

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
    curl -sLo ${TMP_DIR}/install-oms-operator.yaml https://raw.githubusercontent.com/Azure/sterling/$BRANCH_NAME/config/operators/install-oms-operator.yaml
    ${BIN_DIR}/envsubst < ${TMP_DIR}/install-oms-operator.yaml > ${WORKSPACE_DIR}/install-oms-operator-updated.yaml
    ${BIN_DIR}/oc apply -f ${WORKSPACE_DIR}/install-oms-operator-updated.yaml
else
    echo "IBM OMS Operator already installed"
fi


#######
# Create entitlement key secret for image pull

#######
# Create OMS Persistent Volume


#######
# Deploy OMS