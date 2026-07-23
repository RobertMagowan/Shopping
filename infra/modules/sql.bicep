targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param sqlServerName string
param sqlDatabaseName string
param sqlDatabaseSkuName string
param sqlZoneRedundant bool
param sqlDatabaseUseFreeLimit bool
param sqlAdministratorLogin string

@secure()
param sqlAdministratorPassword string

param deploymentPrincipalObjectId string
param sqlEntraAdministratorLogin string
param tags object

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    ...(environmentName == 'dev' ? {
      administratorLogin: sqlAdministratorLogin
      administratorLoginPassword: sqlAdministratorPassword
    } : {})
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: environmentName != 'dev'
      login: sqlEntraAdministratorLogin
      principalType: 'Application'
      sid: deploymentPrincipalObjectId
      tenantId: tenant().tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2025-01-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: sqlDatabaseUseFreeLimit ? {
    name: sqlDatabaseSkuName
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  } : {
    name: sqlDatabaseSkuName
  }
  properties: {
    zoneRedundant: sqlZoneRedundant
    ...(sqlDatabaseUseFreeLimit ? {
      autoPauseDelay: 60
      minCapacity: json('0.5')
      maxSizeBytes: 34359738368
      requestedBackupStorageRedundancy: 'Local'
      useFreeLimit: true
      freeLimitExhaustionBehavior: 'AutoPause'
    } : {})
  }
}

resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = if (!enablePrivateEndpoints) {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerId string = sqlServer.id
output sqlDatabaseName string = sqlDatabase.name
output sqlServerFullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
