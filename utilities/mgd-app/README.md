# Create an Azure managed application in a subscription

This script will create the required storage accounts and blobs if required, then upload a zip file with the managed application before creating the application definition in the subscription.

A managed application requires the following:
    - A storage account to store the zip file containing the following files at a minimum for the application (this is used during the managed application creation process only),
        - mainTemplate.json
        - createUiDefinition.json
    - A storage account to hold the managed application runtime versions of the application definition (this is where the application deployments are actually run from). This is referred to as the BYO storage account.
    - The BYO storage account is configured for access by the Appliance Resource Provider which runs the managed application deployment.

# Instructions

1. Clone this repsoitory
2. Create the zip file containing the mainTemplate.json and createUiDefinition.json files (note that these are case senstive and must be at the root level of the zip file)
3. Copy the zip file to the same directory as the `mgd-app` scripts.
4. From the `mgd-app` directory, run `./create-mgd-app.sh` 
5. Follow the prompts and enter the details as requested.
    1. Storage account name - this is the storage account to store the zip files only
    2. Resource group name - this is the resource group for the storage account and can also be used as the resource group for the other components
    3. If this is a new storage account, you need to manually add at a minimum your user to the "Storage Blob Data Contributor" role for the storage account via the portal. The script will wait for you to confirm that this has been completed before proceeding (note it can take a few minutes for the change to take affect)
    4. Store container name within the storage account - this is the container in which the zip file will be stored
    5. The file to upload - this is the name of the zip file copied to the `mgd-app` directory earlier
    6. BYO storage account name - this is the storage account that will hold the managed application definition
    7. The BYO resource group name can be the same as the earlier one or a new one.
    8. You will be asked to confirm the creation of the role assignment for the storage account
    9. You will be asked for the security group display name for that will have read access to the managed application. Refer to the Azure AD for the subscription to create a new security group if one does not exist.
    10. You will be asked to confirm the creation of the application definition
    11. The resource group for the application definition can be the same as the resource group for the other components earlier or a different one.

# Using a managed application

Once the managed application is finished, a "service catalog managed application definition" is created in the resource group. Go into the managed application and select "Deploy from definition". This will take you into the uiDefinition screen. The Application Details section is used to define what how the application will be displayed in the resource group and also what the separate, managed application only, resource group name will be. 