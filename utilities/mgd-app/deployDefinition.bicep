param location string = resourceGroup().location

@description('Name of the managed application definition.')
param managedApplicationDefinitionName string

@description('Resource ID for the bring your own storage account where the definition is stored.')
param definitionStorageResourceID string

@description('The URI of the .zip package file.')
param packageFileUri string

@description('Publishers Principal ID that needs permissions to manage resources in the managed resource group.')
param principalId string

@description('Role ID for permissions to the managed resource group.')
param roleId string

@description('Display name for the application')
param definitionDisplayName string

@description('Description of the managed application')
param definitionDescription string

var definitionLockLevel = 'ReadOnly'

resource managedApplicationDefinition 'Microsoft.Solutions/applicationDefinitions@2021-07-01' = {
  name: managedApplicationDefinitionName
  location: location
  properties: {
    lockLevel: definitionLockLevel
    description: definitionDescription
    displayName: definitionDisplayName
    packageFileUri: packageFileUri
    storageAccountId: definitionStorageResourceID
    authorizations: [
      {
        principalId: principalId
        roleDefinitionId: roleId
      }
    ]
  }
}
