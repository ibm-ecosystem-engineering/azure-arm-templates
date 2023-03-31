# Private Container Registry

Deploys a private Azure container registry

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fstorage%2Fprivate-cr%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fstorage%2Fprivate-cr%2Fazuredeploy.json)

## Resources

Deploys the following resources:
- Registry
- Subnet (use `createSubnet` if to be built, otherwise provide `subnetName` of existing subnet)
- Private DNS Zones
- Private DNS Zone Groups
- Virtual network link for the private endpoint
- Private endpoint
- Analytics workspace (use `createAnalyticsWorkspace` if required, otherwise provide `workspaceName` )