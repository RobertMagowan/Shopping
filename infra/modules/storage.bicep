targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param storageAccountName string
param productImagesContainerName string
param tags object

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: environmentName == 'prod' ? 'Standard_ZRS' : 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource productImagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/${productImagesContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output storageBlobEndpoint string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}'
output productImagesContainerName string = productImagesContainerName
