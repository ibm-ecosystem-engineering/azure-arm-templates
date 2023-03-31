# Azure PostgreSQL server

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fdatabase%2Fpostgresql%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fdatabase%2Fpostgresql%2Fazuredeploy.json)

Deploys an Azure PostgreSQL server instance with a private link.

## Resources

Deploys the following resources:
- Subnet (if not provided)
- Private DNS Zone
- Virtual network link for private DNS zone
- Diagnostics Workspace (if required)
- Diagnostic Analytics (if required)