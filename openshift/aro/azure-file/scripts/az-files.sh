#!/bin/bash

######
# Check environment variables
ENV_VAR_NOT_SET=""
if [[ -z $RESOURCE_GROUP ]]; then ENV_VAR_NOT_SET="RESOURCE_GROUP"; fi
if [[ -z $STORAGE_ACCOUNT_NAME ]]; then ENV_VAR_NOT_SET="STORAGE_ACCOUNT_NAME"; fi
if [[ -z $CLIENT_ID ]]; then ENV_VAR_NOT_SET="CLIENT_ID"; fi
if [[ -z $CLIENT_SECRET ]]; then ENV_VAR_NOT_SET="CLIENT_SECRET"; fi
if [[ -z $TENANT_ID ]]; then ENV_VAR_NOT_SET="TENANT_ID"; fi
if [[ -z $SUBSCRIPTION_ID ]]; then ENV_VAR_NOT_SET="SUBSCRIPTION_ID"; fi
if [[ -z $ARO_CLUSTER ]]; then ENV_VAR_NOT_SET="ARO_CLUSTER"; fi


if [[ -n $ENV_VAR_NOT_SET ]]; then
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

######
# Set defaults
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="/workspace"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="azure-file"; fi
if [[ -z $FILE_TYPE ]]; then FILE_TYPE="Premium_LRS"; fi

# Setup workspace
mkdir -p $WORKSPACE_DIR

# Setup temporary directory
mkdir -p $TMP_DIR

#####
# Download OC and kubectl
ARCH=$(uname -m)
OC_FILETYPE="linux"

OC_URL="https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/stable/openshift-client-${OC_FILETYPE}.tar.gz"

# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    echo "INFO: Downloading and installing oc and kubectl"
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
        echo "INFO: Successfully logged on with service principal"
    fi
    az account set --subscription "$SUBSCRIPTION_ID" > /dev/null 2>&1
    if (( $? != 0 )); then
        echo "ERROR: Unable to use subscription id $SUBSCRIPTION_ID. Please check and try agian."
        exit 1
    else
        echo "INFO: Successfully changed to subscription : $(az account show --query name -o tsv)"
    fi
else
    echo "INFO: Using existing Azure CLI login"
fi

#######
# Login to cluster
if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
    echo "INFO: Logging into OpenShift cluster $ARO_CLUSTER"
    API_SERVER=$(az aro list --query "[?contains(name,'$ARO_CLUSTER')].[apiserverProfile.url]" -o tsv)
    CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
    ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD
else   
    CURRENT_SERVER=$(${BIN_DIR}/oc status | grep server | awk '{printf $6}' | sed -e 's#^https://##; s#/##')
    API_SERVER=$(az aro list --query "[?contains(name,'$CLUSTER')].[apiserverProfile.url]" -o tsv)
    if [[ $CURRENT_SERVER == $API_SERVER ]]; then
        echo "INFO: Already logged into cluster"
    else
        CLUSTER_PASSWORD=$(az aro list-credentials --name $ARO_CLUSTER --resource-group $RESOURCE_GROUP --query kubeadminPassword -o tsv)
        ${BIN_DIR}/oc login $API_SERVER -u kubeadmin -p $CLUSTER_PASSWORD
    fi
fi

######
# Wait for cluster operators to finish
count=0
while [[ $(${BIN_DIR}/oc get clusteroperators -o json | jq -r '.items[].status.conditions[] | select(.type=="Available") | .status' | grep False) ]]; do
    echo "INFO: Waiting for cluster operators to finish installation. Waited $count minutes. Will wait up to 30 minutes."
    sleep 60
    count=$(( $count + 1 ))
    if (( $count > 60 )); then
        echo "ERROR: Timeout waiting for cluster operators to be available"
        exit 1;    
    fi
done
echo "INFO: All OpenShift cluster operators available"

export LOCATION=$(az group show --resource-group $RESOURCE_GROUP --query location -o tsv)

#####
# Check that storage account exists
az storage account show -n $STORAGE_ACCOUNT_NAME -g $RESOURCE_GROUP > /dev/null 2>&1
if (( $? != 0 )); then
    echo "ERROR: Storage account $STORAGE_ACCOUNT_NAME does not exist"
    exit 1
    # Below is not a secure access method but does work for testing
    #az storage account create \
    # --name $STORAGE_ACCOUNT_NAME \
    # --resource-group $RESOURCE_GROUP \
    # --location $LOCATION \
    # --https-only false \
    # --allow-shared-key-access true \
    # --allow-blob-public-access false \
    # --sku Premium_LRS \
    # --public-network-access Enabled \
    # --kind FileStorage \
    # --enable-large-file-share 
else
    echo "INFO: Storage account, $STORAGE_ACCOUNT_NAME, exists"
fi

#####
# Set ARO cluster permissions
if [[ $(${BIN_DIR}/oc get clusterrole | grep azure-secret-reader) ]]; then
    echo "INFO: Using existing cluster role"
else
    echo "INFO: Creating cluster role and policy"
    ${BIN_DIR}/oc create clusterrole azure-secret-reader --verb=create,get --resource=secrets
    ${BIN_DIR}/oc adm policy add-cluster-role-to-user azure-secret-reader system:serviceaccount:kube-system:persistent-volume-binder
fi

#####
# Create storage class

if [[ -z $(${BIN_DIR}/oc get sc | grep ${SC_NAME}) ]]; then
    echo "INFO: Creating Azure files storage class $SC_NAME"
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

    ${BIN_DIR}/oc create -f ${WORKSPACE_DIR}/azure-storageclass-azure-file.yaml
else
    echo "INFO: Azure file storage class $SC_NAME already exists"
fi