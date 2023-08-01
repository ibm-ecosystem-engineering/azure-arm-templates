# Deploy an OpenShift IPI cluster in Azure

## Prerequisites

1. Service principal
2. Assign subscription contributor role to service principal

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



## Delete an existing cluster

To delete a cluster, perform the following.

```bash
CLUSTER_NAME="<cluster_name>"
LOCATION="<location>"


cat << EOF >> ./metadata.json
{
    "clusterName": "crenolyh",
    "clusterID": "5231ca80-2a93-4463-a0d7-80bd6cb76d25",
    "infraID": "crenolyh-h5n9f",
    "azure": {
        "armEndpoint": "",
        "cloudName": "AzurePublicCloud",
        "region": "$LOCATION",
        "resourceGroupName": "",
        "baseDomainResourceGroupName": "ocp-domain"
    }
}
EOF

```

Then optionally remove the service principal role definitions created earlier.