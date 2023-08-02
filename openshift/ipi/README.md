# Deploy an OpenShift IPI cluster in Azure

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fopenshift%2Fipi%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fopenshift%2Fipi%2Fazuredeploy.json)

## Prerequisites

1. Service principal
2. Assign subscription contributor & user access administrator role to service principal

```bash
SP_NAME="<service_principal_name>"
SP_OBJECT_ID="$(az ad sp list --display-name $SP_NAME --query '[0].id' -o tsv)"
SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
CONTRIBUTOR_ROLE_ID="$(az role definition list --name "Contributor" --query '[0].name' -o tsv)"
USER_ACCESS_ROLE_ID="$(az role definition list --name "User Access Administrator" --query '[0].name' -o tsv)"
az role assignment create --assignee $SP_OBJECT_ID --subscription $SUBSCRIPTION_ID --role $CONTRIBUTOR_ROLE_ID
az role assignment create --assignee $SP_OBJECT_ID --subscription $SUBSCRIPTION_ID --role $USER_ACCESS_ROLE_ID
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

## Delete an existing cluster

To delete a cluster, perform the following. It is not recommended to delete just the resource group as this will leave the DNS zone files which may cause problems with future deployments.

```bash
RESOURCE_GROUP="<resource_group>"
CLUSTER_NAME="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.clusterName.value' -o tsv)"
CLUSTER_ID="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.clusterId.value' -o tsv)"
INFRA_ID="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.outputs.infraId.value' -o tsv)"
BASE_DOMAIN_RG="$(az deployment group show -g $RESOURCE_GROUP -n deploy-ocp-ipi --query 'properties.parameters.baseDomainRG.value' -o tsv)"
LOCATION="az group show -g $RESOURCE_GROUP --query 'location' -o tsv"

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