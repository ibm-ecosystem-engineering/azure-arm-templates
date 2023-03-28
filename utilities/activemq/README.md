# Azure ActiveMQ Virtual Machine

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

## Instructions

The following instructions assume the use of the Azure CLI to deploy. It is also possible to use this deployment template through the Azure portal as part of a custom template deployment. 

Clone this repository locally.

    ```shell
    $ git clone https://github.com/ibm-ecosystem-lab/azure-arm-templates.git
    ```

The following are examples of the configurations that can be deployed. Customize by changing the parameters supplied. Refer to the azuredeploy file parameters section for details.

### Create with new Virtual Network with Public IP

```shell
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

```shell
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

Post deployment the admin console for ActiveMQ is available at `https://<vm-ip>:8161/admin`.
    
The `<vm-ip>` will either be the internal IP address of the VM or the public IP depending upon whether a public IP was selected.

The credentials will be admin and the password entered during the deployment.