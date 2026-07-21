targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param redisName string
param managedRedisSkuName string
param keyVaultName string
param tags object

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource redis 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: redisName
  location: location
  tags: tags
  sku: {
    name: managedRedisSkuName
  }
  properties: {
    encryption: {}
    highAvailability: environmentName == 'prod' ? 'Enabled' : 'Disabled'
    minimumTlsVersion: '1.2'
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
  }
}

resource redisDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  parent: redis
  name: 'default'
  properties: {
    accessKeysAuthentication: 'Enabled'
    clientProtocol: 'Encrypted'
    clusteringPolicy: 'NoCluster'
    evictionPolicy: 'AllKeysLRU'
    port: 10000
  }
}

resource redisConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'shopping-web-redis-connection-string'
  properties: {
    value: '${redis.properties.hostName}:${redisDatabase.properties.port},password=${redisDatabase.listKeys().primaryKey},ssl=True,abortConnect=False'
  }
}

output redisName string = redis.name
output redisId string = redis.id
output redisConnectionStringSecretUri string = redisConnectionStringSecret.properties.secretUri
