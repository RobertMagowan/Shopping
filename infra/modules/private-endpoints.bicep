targetScope = 'resourceGroup'

param location string
param virtualNetworkName string
param virtualNetworkId string
param privateEndpointSubnetId string
param storageAccountName string
param storageAccountId string
param sqlServerName string
param sqlServerId string
param keyVaultName string
param keyVaultId string
param redisName string
param redisId string
param containerRegistryName string
param containerRegistryId string
param blobPrivateDnsZoneName string
param sqlPrivateDnsZoneName string
param tags object

var privateDnsZoneNames = [
  blobPrivateDnsZoneName
  sqlPrivateDnsZoneName
  'privatelink.vaultcore.azure.net'
  'privatelink.redis.azure.net'
  'privatelink.azurecr.io'
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource privateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in privateDnsZoneNames: {
  parent: privateDnsZones[index]
  name: '${virtualNetworkName}-${index}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}]

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'blob'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${sqlServerName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'sql'
        properties: {
          privateLinkServiceId: sqlServerId
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${redisName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'redis'
        properties: {
          privateLinkServiceId: redisId
          groupIds: [
            'redisEnterprise'
          ]
        }
      }
    ]
  }
}

resource containerRegistryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${containerRegistryName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'registry'
        properties: {
          privateLinkServiceId: containerRegistryId
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource storagePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: privateDnsZones[0].id
        }
      }
    ]
  }
}

resource sqlPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql'
        properties: {
          privateDnsZoneId: privateDnsZones[1].id
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: privateDnsZones[2].id
        }
      }
    ]
  }
}

resource redisPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: redisPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'redis'
        properties: {
          privateDnsZoneId: privateDnsZones[3].id
        }
      }
    ]
  }
}

resource containerRegistryPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: containerRegistryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'registry'
        properties: {
          privateDnsZoneId: privateDnsZones[4].id
        }
      }
    ]
  }
}
