# Deploy an OpenShift IPI cluster in Azure

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fopenshift%2Fipi%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fopenshift%2Fipi%2Fazuredeploy.json)

## Prerequisites

1. Service principal
2. Assign subscription contributor & user access administrator role to service principal

```bash
SP_NAME="<service_principal_name>"
SP_OBJECT_ID="$(az ad sp list --display-name $SP_NAME --query '[0].id' -o tsv)"
CLIENT_ID="$(az ad sp list --display-name $SP_NAME --query '[0].appId' -o tsv)"
SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
CONTRIBUTOR_ROLE_ID="$(az role definition list --name "Contributor" --query '[0].name' -o tsv)"
USER_ACCESS_ROLE_ID="$(az role definition list --name "User Access Administrator" --query '[0].name' -o tsv)"
az role assignment create --assignee $SP_OBJECT_ID --subscription $SUBSCRIPTION_ID --role $CONTRIBUTOR_ROLE_ID
az role assignment create --assignee $SP_OBJECT_ID --subscription $SUBSCRIPTION_ID --role $USER_ACCESS_ROLE_ID
```

## Create the cluster - CLI

```shell
# Get the resource group name and location
echo -n "Enter the resource group name : "
read RESOURCE_GROUP

echo -n "Enter the location : "
read LOCATION

echo -n "Enter the name prefix : "
read NAME_PREFIX

# Modify these as required  
BRANCH="108-add-azure-file-option-for-ocp-ipi"
DOMAIN_RG="ocp-domain"
BASE_DOMAIN="ibmeebpazure.net"
VNET_CIDR="10.0.0.0/20"
CONTROL_SUBNET_CIDR="10.0.0.0/24"
WORKER_SUBNET_CIDR="10.0.1.0/24"
VNET_NAME="vnet"
CONTROL_SUBNET_NAME="control-subnet"
WORKER_SUBNET_NAME="worker-subnet"
WORKER_NODE_SIZE="Standard_D16s_v4"
WORKER_NODE_QTY=3
OCP_VERSION="4.12"
PULL_SECRET="$(cat ~/Downloads/pull-secret)"
STORAGE_SIZE="1Ti"

# Login to the Azure CLI if not already
az login

# Set defaults (can be changed, or leave as is)
SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
TAGS="created-by=$(az account show --query 'user.name' -o tsv)"

# Create resource group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION \
    --tags "$TAGS"

# Call deployment
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --name "ocp-deployment" \
    --mode Incremental \
    --template-uri "https://raw.githubusercontent.com/ibm-ecosystem-engineering/azure-arm-templates/$BRANCH/openshift/ipi/azuredeploy.json" \
    --parameters namePrefix="$NAME_PREFIX" \
    --parameters baseDomain="$BASE_DOMAIN" \
    --parameters baseDomainRG="$DOMAIN_RG" \
    --parameters vnetName="$VNET_NAME" \
    --parameters vnetCIDR="$VNET_CIDR" \
    --parameters controlSubnetName="$CONTROL_SUBNET_NAME" \
    --parameters controlSubnetCIDR="$CONTROL_SUBNET_CIDR" \
    --parameters workerSubnetName="$WORKER_SUBNET_NAME" \
    --parameters workerSubnetCIDR="$WORKER_SUBNET_CIDR" \
    --parameters workerNodeSize="$WORKER_NODE_SIZE" \
    --parameters workerNodeQty="$WORKER_NODE_QTY" \
    --parameters ocpVersion="$OCP_VERSION" \
    --parameters clientId="$CLIENT_ID" \
    --parameters clientObjectId="$SP_OBJECT_ID" \
    --parameters pullSecret="$PULL_SECRET" \
    --parameters branch="$BRANCH"

# Get cluster login parameters
API_SERVER=$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.apiServer.value' -o tsv)
OCP_USERNAME=$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.adminUser.value' -o tsv)
OCP_PASSWORD=$(az deployment-scripts list -g $RESOURCE_GROUP --query "[?contains(name, 'ocp-deploy-script')] | [?contains(provisioningState, 'Succeeded')].outputs.clusterDetails.adminPassword" -o tsv)
STORAGE_ACCOUNT_NAME=$(az deployment group show -g $RESOURCE_GROUP -n "ocp-deployment" --query 'properties.parameters.storageAccountName.value' -o tsv)
MANAGED_ID_NAME=$(az deployment group show -g $RESOURCE_GROUP -n "ocp-deployment" --query 'properties.parameters.managedIdName.value' -o tsv)

# Add ODF
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --name "odf-deployment" \
    --mode Incremental \
    --template-uri "https://raw.githubusercontent.com/ibm-ecosystem-engineering/azure-arm-templates/$BRANCH/openshift/ipi/odf/azuredeploy.json" \
    --parameters namePrefix="$NAME_PREFIX" \
    --parameters apiServer="$API_SERVER" \
    --parameters ocpUsername="$OCP_USERNAME" \
    --parameters ocpPassword="$OCP_PASSWORD" \
    --parameters storageSize="$STORAGE_SIZE" \
    --parameters existingNodes="yes" \
    --parameters createStorageAccount=false \
    --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" \
    --parameters createManagedIdentity=false \
    --parameters managedIdName="$MANAGED_ID_NAME" \
    --parameters branch="$BRANCH"

```


## Retrieve cluster login credentials

```bash
RESOURCE_GROUP="<resource_group>"
az deployment group list -o table -g $RESOURCE_GROUP

# Console
CONSOLE_URL=$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.consoleURL.value' -o tsv)
ADMIN_USER=$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.adminUser.value' -o tsv)
ADMIN_PASSWORD=$(az deployment-scripts list -g $RESOURCE_GROUP --query "[?contains(name, 'ocp-deploy-script')] | [?contains(provisioningState, 'Succeeded')].outputs.clusterDetails.adminPassword" -o tsv)
```

## Login to cluster via CLI

```bash
RESOURCE_GROUP="<resource_group>"

API_SERVER=$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.apiServer.value' -o tsv)
OCP_USERNAME=$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.adminUser.value' -o tsv)
OCP_PASSWORD=$(az deployment-scripts list -g $RESOURCE_GROUP --query "[?contains(name, 'ocp-deploy-script')] | [?contains(provisioningState, 'Succeeded')].outputs.clusterDetails.adminPassword" -o tsv)

oc login $API_SERVER -u $OCP_USERNAME -p $OCP_PASSWORD --insecure-skip-tls-verify=true
```

## Delete an existing cluster

To delete a cluster, perform the following. It is not recommended to delete just the resource group as this will leave the DNS zone files which may cause problems with future deployments.

```bash
RESOURCE_GROUP="<resource_group>"
CLUSTER_NAME="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.clusterName.value' -o tsv)"
CLUSTER_ID="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.clusterId.value' -o tsv)"
INFRA_ID="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.infraId.value' -o tsv)"
BASE_DOMAIN_RG="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.parameters.baseDomainRG.value' -o tsv)"
LOCATION="$(az group show -g $RESOURCE_GROUP --query 'location' -o tsv)"

# If not already, install the openshift-install tool

# Create the Azure credentials file if it does not exist
SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
TENANT_ID="$(az account show --query 'tenantId' -o tsv)"
CLIENT_ID="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.parameters.clientId.value' -o tsv)"
CLIENT_SECRET="<client_secret>"

cat << EOF > ~/.azure/osServicePrincipal.json
{
    "subscriptionId":"$SUBSCRIPTION_ID",
    "clientId":"$CLIENT_ID",    
    "clientSecret":"$CLIENT_SECRET",
    "tenantId":"$TENANT_ID"
}
EOF
chmod 600 ~/.azure/osServicePrincipal.json

# Create metadata
mkdir -p /tmp/$INFRA_ID
cat << EOF > /tmp/$INFRA_ID/metadata.json
{
    "clusterName": "$CLUSTER_NAME",
    "clusterID": "$CLUSTER_ID",
    "infraID": "$INFRA_ID",
    "azure": {
        "armEndpoint": "",
        "cloudName": "AzurePublicCloud",
        "region": "$LOCATION",
        "resourceGroupName": "",
        "baseDomainResourceGroupName": "$BASE_DOMAIN_RG"
    }
}
EOF

# Destroy cluster
openshift-install destroy cluster --dir /tmp/$INFRA_ID --log-level=debug

# Destroy the resource group
az group delete --name $RESOURCE_GROUP --yes

```

Then optionally remove the service principal role definitions created earlier.


```bash
SP_NAME="<service_principal_name>"
SP_OBJECT_ID="$(az ad sp list --display-name $SP_NAME --query '[0].id' -o tsv)"
SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
CONTRIBUTOR_ROLE_ID="$(az role definition list --name "Contributor" --query '[0].name' -o tsv)"
USER_ACCESS_ROLE_ID="$(az role definition list --name "User Access Administrator" --query '[0].name' -o tsv)"

az role assignment delete --assignee $SP_OBJECT_ID --subscription $SUBSCRIPTION_ID --role $CONTRIBUTOR_ROLE_ID
az role assignment delete --assignee $SP_OBJECT_ID --subscription $SUBSCRIPTION_ID --role $USER_ACCESS_ROLE_ID
```
