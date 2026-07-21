targetScope = 'resourceGroup'

param environmentName string
param location string
param enablePrivateEndpoints bool
param logAnalyticsName string
param applicationInsightsName string
param containerAppsEnvironmentName string
param containerAppsInfrastructureSubnetId string
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environmentName == 'prod' ? 90 : 30
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: union({
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: environmentName == 'prod'
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }, enablePrivateEndpoints ? {
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsInfrastructureSubnetId
      internal: false
    }
  } : {})
}

output containerAppsEnvironmentId string = containerAppsEnvironment.id
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
