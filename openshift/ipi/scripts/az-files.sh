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
if [[ -z $API_SERVER ]]; then ENV_VAR_NOT_SET="API_SERVER"; fi
if [[ -z $OCP_USERNAME ]]; then ENV_VAR_NOT_SET="OCP_USERNAME": fi
if [[ -z $OCP_PASSWORD ]]; then ENV_VAR_NOT_SET="OCP_PASSWORD"; fi



if [[ -n $ENV_VAR_NOT_SET ]]; then
    echo "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

######
# Set defaults
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$(pwd)"; fi
if [[ -z $BIN_DIR ]]; then export BIN_DIR="/usr/local/bin"; fi
if [[ -z $TMP_DIR ]]; then TMP_DIR="${WORKSPACE_DIR}/tmp"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="azure-file"; fi
if [[ -z $FILE_TYPE ]]; then FILE_TYPE="Premium_LRS"; fi

# Setup workspace
mkdir -p $WORKSPACE_DIR

# Setup temporary directory
mkdir -p $TMP_DIR

# Download and install CLI's if they do not already exist
if [[ ! -f ${BIN_DIR}/oc ]] || [[ ! -f ${BIN_DIR}/kubectl ]]; then
    cli-download $BIN_DIR $TMP_DIR
fi

#######
# Login to Azure CLI
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Login with service principal details
    az-login $CLIENT_ID $CLIENT_SECRET $TENANT_ID $SUBSCRIPTION_ID
else
    log-output "INFO: Using existing Azure CLI login"
fi

##### 
# Wait for cluster operators to complete implementation and startup
wait_for_cluster_operators $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

#######
# Login to cluster
oc-login $API_SERVER $OCP_USERNAME $OCP_PASSWORD $BIN_DIR

export LOCATION=$(az group show --resource-group $RESOURCE_GROUP --query location -o tsv)

#####
# Check that storage account exists
az storage account show -n $STORAGE_ACCOUNT_NAME -g $RESOURCE_GROUP > /dev/null 2>&1
if (( $? != 0 )); then
    echo "ERROR: Storage account $STORAGE_ACCOUNT_NAME does not exist"
    exit 1
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
    cat << EOF | oc -f -
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


else
    echo "INFO: Azure file storage class $SC_NAME already exists"
fi