targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param keyVaultName string

@secure()
param entraExternalIdWebClientSecret string

param tags object

var hasWebClientSecret = !empty(entraExternalIdWebClientSecret)
var purgeProtectionProperties = environmentName == 'prod' ? {
  enablePurgeProtection: true
} : {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: union({
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: environmentName == 'prod' ? 90 : 7
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
  }, purgeProtectionProperties)
}

resource webClientSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (hasWebClientSecret) {
  parent: keyVault
  name: 'entra-external-id-web-client-secret'
  properties: {
    value: entraExternalIdWebClientSecret
  }
}

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output webClientSecretUri string = hasWebClientSecret ? webClientSecret!.properties.secretUri : ''
