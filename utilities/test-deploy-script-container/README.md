# Deploy a test container for Azure ARM Template deployment CLI scripts

This ARM Template run a container with an infinite loop.

Working scripts can then be uploaded to the container and the container can be connected to in order to run in terminal mode.

## Resources

Deploys the following resources:
- Storage account for container and shared files (if required)
- Managed Identity to run container
- Container group with Azure CLI container

# Upload files
1. From the Azure portal, navigate to the resource group
2. Open the `<prefix>deployscript` storage account
3. Navigate to file shares
4. Open the share (will have a random name)
    - `azscriptinput` is the shared directory on the container that contains the running script
5. Upload your scripts as required

# Connect to container
1. From the Azure portal, navigate to the `<prefix>-cg` container group. 
2. Navigate to `Containers`
3. Click on connect and open terminal