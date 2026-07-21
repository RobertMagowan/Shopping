targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param sqlServerName string
param sqlDatabaseName string
param sqlDatabaseSkuName string
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

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: sqlDatabaseSkuName
  }
  properties: {
    zoneRedundant: environmentName == 'prod'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerId string = sqlServer.id
output sqlDatabaseName string = sqlDatabase.name
output sqlServerFullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
