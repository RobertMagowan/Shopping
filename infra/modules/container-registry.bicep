targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param containerRegistryName string
param containerRegistrySkuName string
param tags object

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySkuName
  }
  properties: union({
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
  }, environmentName == 'prod' ? {
    zoneRedundancy: 'Enabled'
  } : {})
}

output containerRegistryName string = containerRegistry.name
output containerRegistryId string = containerRegistry.id
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
