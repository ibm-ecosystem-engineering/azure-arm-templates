#!/bin/bash

source common.sh

# Set defaults
if [[ -z $OUTPUT_DIR ]]; then export OUTPUT_DIR="/tmp"; fi

# Create new log output file
reset-output

# Check environment variables
ENV_VAR_NOT_SET=""

if [[ -n $ENV_VAR_NOT_SET ]]; then
    log-output "ERROR: $ENV_VAR_NOT_SET not set. Please set and retry."
    exit 1
fi

# Log into Azure
az account show > /dev/null 2>&1
if (( $? != 0 )); then
    # Interactive login
    az login 
else
    log-output "Using existing Azure CLI login"
fi


# Create storage account
echo
echo -n "Enter the name of the storage account for the application files: "
read storage_account_name

if [[ -z $(az storage account list -o table | grep $storage_account_name ) ]]; then
    confirm=""
    echo
    echo -n "Storage account $storage_account_name does not exist. Create? [Y/n]: "
    read confirm

    if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

        # Create resource group for storage
        echo
        echo -n "Enter name for new resource group for storage account : "
        read resource_group_name

        if [[ -z $(az group list -o table | grep $resource_group_name ) ]]; then

            confirm=""
            echo
            echo -n "Resource group $resource_group_name does not exist. Create? [Y/n]: "
            read confirm

            if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

                region=$(get_region)

                az group create --name $resource_group_name --location $region > /dev/null 2>&1
                if (( $? != 0 )); then
                    log-output "ERROR: Unable to create resource group $resource_group_name in $location"
                    exit 1
                else
                    log-output "INFO: Successfully created resource group"
                fi

            else
                log-output "ERROR: No existing resource group $resource_group_name"
                exit 1
            fi
        fi

        # Create storage account
        location=$(az group show --name $resource_group_name --query location -o tsv)

        if ! error=$(az storage account create --name $storage_account_name --resource-group $resource_group_name --location $location --allow-blob-public-access true --sku Standard_LRS --kind StorageV2 2>&1); then
            log-output "ERROR: Unable to create storage account $storage_account_name in resource group $resource_group_name in location $location"
            log-output "$error"
            exit 1
        else
            log-output "INFO: Successfully created storage account $storage_account_name"
        fi
    else
        log-output "ERROR: No existing storage account $storage_account_name"
        exit 1
    fi
else
     log-output "INFO: Using existing storage account $storage_account_name"
fi

########
# Manually create a role assignment for the above storage account
# az role assignment create \
#     --role "Storage Blob Data Contributor" \
#     --assignee <email> \
#     --scope "/subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.Storage/storageAccounts/<storage-account>/blobServices/default/containers/<container>"
confirm=""
echo 
echo -n "Please manually add storage data contributor role to the created storage account $storage_account_name. Confirmed [Y]: "
read confirm


if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) != "Y" ]] && [[ ! -z $confirm ]]; then
    log-output "ERROR: Exiting as role update not confirmed"
    exit 1
fi

# Create storage container and upload application
storage_container_name=""
echo
echo -n "Enter name of storage container to store application files: "
read storage_container_name

if [[ -z $(az storage container list --account-name $storage_account_name --auth-mode login -o table | grep $storage_container_name ) ]]; then
    confirm=""
    echo 
    echo -n "Create storage container and upload application [Y/n]: "
    read confirm
    if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

        if error=$(az storage container create --account-name $storage_account_name --name $storage_container_name --auth-mode login --public-access blob 2>&1); then
            log-output "INFO: Successfully created storage container $storage_container_name"
        else
            log-output "ERROR: Unable to create storage container $storage_container_name in storage account $storage_account_name"
            log-output "$error"
            exit 1
        fi
    else
        log-output "ERROR: No existing storage container $storage_container_name in storage account $storage_account_name"
        exit 1
    fi
else
    log-output "INFO: Using existing storage container $storage_container_name in storage account $storage_account_name"
fi

# Upload application to blob storage
echo
echo -n "Enter the name of the file to upload or use (must be in current directory): "
read zip_file_name

if [[ -z $(az storage blob list --container-name $storage_container_name --account-name $storage_account_name --auth-mode login --output table | grep $zip_file_name) ]]; then
    confirm=""
    echo
    echo -n "File does not exist blob storage. Upload? [Y/n]: "
    read confirm

    if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

        az storage blob upload \
            --account-name $storage_account_name \
            --container-name $storage_container_name \
            --auth-mode login \
            --name "$zip_file_name" \
            --file "$zip_file_name" 

    else
        log-output "ERROR: Blob is required to be in storage container to proceed. Exiting."
        exit 0
    fi   
else
    log-output "INFO: Blob $zip_file_name already exists in $storage_account_name."
fi  

packageuri=$(az storage blob url \
  --account-name $storage_account_name \
  --container-name $storage_container_name \
  --auth-mode login \
  --name $zip_file_name --output tsv)

# Create BYO Storage for the managed application definition
echo
echo -n "Enter BYO storage account name: "
read byo_storage_account_name

echo
echo -n "Enter resource group for BYO storage account [$resource_group_name] : "
read byo_resource_group_name

if [[ -z $byo_resource_group_name ]]; then
    byo_resource_group_name=$resource_group_name
fi

if [[ -z $(az storage account list -o table | grep $byo_storage_account_name ) ]]; then
    confirm=""
    echo
    echo -n "Create BYO Storage Account [Y/n]: "
    read confirm 

    if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then
        # Create resource group for storage

        if [[ -z $(az group list -o table | grep $byo_resource_group_name ) ]]; then

            confirm=""
            echo
            echo -n "Resource group $byo_resource_group_name does not exist. Create? [Y/n]: "
            read confirm

            if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

                region=$(get_region)

                az group create --name $byo_resource_group_name --location $region > /dev/null 2>&1
                if (( $? != 0 )); then
                    log-output "ERROR: Unable to create resource group $byo_resource_group_name in $region"
                    exit 1
                else
                    log-output "INFO: Successfully created resource group"
                fi

            else
                log-output "ERROR: No existing resource group $byo_resource_group_name"
                exit 1
            fi
        else
            log-output "INFO: Resource group $byo_resource_group_name already exists."
        fi

        location=$(az group show --name $byo_resource_group_name --query location -o tsv)

        az storage account create \
            --name $byo_storage_account_name \
            --resource-group $byo_resource_group_name \
            --location $location \
            --sku Standard_LRS \
            --kind StorageV2

        sleep 20

        log-output "INFO: Created BYO storage account $byo_storage_account_name"

    else
        log-output "INFO: Using existing BYO storage account $byo_storage_account_name"
    fi
else
    log-output "INFO: BYO Storage account $byo_storage_account_name already exists."
fi

storageid=$(az storage account show --resource-group $byo_resource_group_name --name $byo_storage_account_name --query id --output tsv)

# Set the role assignment for the BYO storage account
confirm=""
echo
echo -n "Set role assignment for Appliance Resource Provider [Y/n]: "
read confirm

if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then
    arpid=$(az ad sp list --display-name "Appliance Resource Provider" --query [].id --output tsv)

    az role assignment create --assignee $arpid \
    --role "Contributor" \
    --scope $storageid
else
    log-output "INFO: Using existing role assignment"
fi

# Get group id and role definition id for the managing group
echo
echo -n "Enter the display name of the managing security group for the application: "
read management_group_name

principalid=$(az ad group show --group $management_group_name --query id --output tsv)
roleid=$(az role definition list --name Owner --query "[].name" --output tsv)

# Deploy the application definition
confirm=""
echo
echo "Create application definition [Y/n]: "
read confirm

if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

    echo
    echo -n "Please enter application definition name: "
    read application_definition_name

    echo
    echo -n "Enter the resource group for the application definitions [$byo_resource_group_name]: "
    read app_resource_group_name

    if [[ -z $byo_resource_group_name ]]; then
        app_resource_group_name=$byo_resource_group_name
    fi

    if [[ -z $(az group list -o table | grep $app_resource_group_name ) ]]; then

        confirm=""
        echo
        echo -n "Resource group $app_resource_group_name does not exist. Create? [Y/n]: "
        read confirm

        if [[ $(echo $confirm | tr '[:lower:]' '[:upper:]' ) == "Y" ]] || [[ -z $confirm ]]; then

            region=$(get_region)

            az group create --name $app_resource_group_name --location $region > /dev/null 2>&1
            if (( $? != 0 )); then
                log-output "ERROR: Unable to create resource group $app_resource_group_name in $region"
                exit 1
            else
                log-output "INFO: Successfully created resource group"
            fi

        else
            log-output "ERROR: No existing resource group $app_resource_group_name"
            exit 1
        fi
    else
        log-output "INFO: Resource group $app_resource_group_name already exists."
    fi

    az deployment group create \
        --resource-group $app_resource_group_name \
        --template-file deployDefinition.bicep \
        --parameter managedApplicationDefinitionName=$application_definition_name \
        --parameter definitionStorageResourceID=$storageid \
        --parameter packageFileUri=$packageuri \
        --parameter principalId=$principalid \
        --parameter roleId=$roleid
else
    log-output "INFO: Using existing application definition"
fi
