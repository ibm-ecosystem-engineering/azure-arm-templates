# Azure ActiveMQ Virtual Machine

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Futilities%2Factivemq%2Factivemq-vm%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fibm-ecosystem-lab%2Fazure-arm-templates%2Fmain%2Futilities%2Factivemq%2Factivemq-vm%2Fazuredeploy.json)

Deploys an Azure virtual machine with an ActiveMQ server.

## Resources

Deploys the following resources:
- VNet (if required, enabled by default disable by setting createVNet to false)
- Subnet (if required, enabled by default, disable by setting createSubnet to false)
- Network interface
- Network security group for the network interface
- Public IP (if required, disabled by default, enable by setting createPublicIP to true)
- Virtual Machine

    The following images are currently suppoted,
    - Ubuntu 18.04 LTS
    - Ubuntu 20.04 LTS
    - Ubuntu 22.04 LTS
    - RHEL 8.6
- Either the install script for Ubuntu or RHEL versions of ActiveMQ

## Instructions - Portal

1. Click on the `Deploy to Azure` button above.

2. Complete, review and update the parameters.

    ![ActiveMQ Parameters1](./images/activemq-parameters1.png)
    ![ActiveMQ Parameters2](./images/activemq-parameters2.png)

    - Select an existing or create a new resource group
    - Enter a name prefix which will be used for the created resources
    - If using an existing vnet, ensure the vnet name, and subnet name match the existing ones (the CIDR values will not be used for existing VNet)
    - Select the type of authentication. If adding a public IP, it is recommended to use SSH Public Key authentication. For SSH public key authentication, create a new key, use an existing one on Azure or copy & paste one from your local machine.
    - Select the security type. ***Important. TrustedLaunch only works with Ubuntu. Do not select if using RHEL images***
    - Select the OS disk type
    - Select the type of image to deploy
    - Select to create a public IP or not. If creating a public IP, the public IP name and domain name parameters will used.
    
3. When the parameters are complete, click on `Review + Create` at the bottom of the page.

4. Once the parameters are validated, click on `Create` to commence the deployment.

## Instructions - CLI

The following instructions assume the use of the Azure CLI to deploy. It is also possible to use this deployment template through the Azure portal as part of a custom template deployment. 

Clone this repository locally.

    ```
    $ git clone https://github.com/ibm-ecosystem-lab/azure-arm-templates.git
    ```

The following are examples of the configurations that can be deployed. Customize by changing the parameters supplied. Refer to the azuredeploy file parameters section for details.

### Create with new Virtual Network with Public IP

```
$ RESOURCE_GROUP="<rgName>"
$ IMAGE="<osImage>"
$ NAME_PREFIX="<namePrefix>"
$ PASSWORD="<password>"
$ SSH_KEY="$(cat ~/.ssh/id_rsa.pub)"
$ az deployment group create --name <deploymentName> \
    --resource-group $RESOURCE_GROUP \
    --template-file ./utilities/activemq/activemq-vm/azuredeploy.json \
    --parameters namePrefix=$NAME_PREFIX \
    --parameters vmOSVersion=$IMAGE \
    --parameters mqPassword=$PASSWORD \
    --parameters adminPassword=$SSH_KEY
```

### Existing Virtual Network without Public IP

```
$ RESOURCE_GROUP="<rgName>"
$ IMAGE="<osImage>"
$ NAME_PREFIX="<namePrefix>"
$ VNET_NAME="<vnetName>"
$ SUBNET_NAME="<subnetName>
$ az deployment group create --name <deploymentName> \
    --resource-group $RESOURCE_GROUP \
    --template-file ./utilities/activemq/activemq-vm/azuredeploy.json \
    --parameters namePrefix=$NAME_PREFIX \
    --parameters vmOSVersion=$IMAGE \
    --parameters mqPassword=$PASSWORD \
    --parameters authType=password \
    --parameters adminPassword=$PASSWORD \
    --parameters createVNet=false \
    --parameters vnetName=$VNET_NAME \
    --parameters createSubnet=false \
    --parameters subnetName=$SUBNET_NAME
```

## Post deployment

Post deployment the admin console for ActiveMQ is available at `http://<vm-ip>:8161/admin`. See the output from the deployment for details.
    
The `<vm-ip>` will either be the internal IP address of the VM or the public IP depending upon whether a public IP was selected.

The credentials will be admin and the password entered during the deployment.