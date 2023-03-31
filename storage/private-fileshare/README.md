# Create a private file share

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fstorage%2Fprivate-fileshare%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fstorage%2Fprivate-fileshare%2Fazuredeploy.json)

## Resources

Deploys the following resources:
- Storage account 
- Subnet (if required, can be referred to if already existing, use the `createSubnet` parameter to create a subnet)
- Private DNS Zone for the private endpoint
- Virtual network link for the private endpoint
- Private endpoint
- Private DNS Zone group
- File services
- File share
- Analytics Workspace (can be created by setting the `createAnalyticsWorkspace` or provided)
- Diagnostic Settings (if required)
