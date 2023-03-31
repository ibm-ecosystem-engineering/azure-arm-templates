# ARM Template to deploy and configure a developer VM

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fcompute%2Fdev-vm%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Fcompute%2Fdev-vm%2Fazuredeploy.json)

## Login

An admin user and password need to be provided. It is recommended that this VM is only used within a secure environment with a bastion service as the access point.

## Tools

The following tools are installed:
- docker
- helm
- openshift client (oc)

## Networking

An existing subnet can be provided, or a new one can be created. If creating a new subnet, specify the subnet name and the NAT gateway to attach to the subnet.

The VM only has an internal IP address for the VNet. No public IP address.