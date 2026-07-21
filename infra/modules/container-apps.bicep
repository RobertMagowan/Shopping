targetScope = 'resourceGroup'

param location string
param webContainerAppName string
param apiContainerAppName string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param webIdentityResourceId string
param apiIdentityResourceId string
param apiIdentityClientId string
param webContainerImage string
param apiContainerImage string
param containerResources object
param containerAppMinReplicas int
param containerAppMaxReplicas int
param aspNetCoreEnvironment string
param applicationInsightsConnectionString string
param entraExternalIdInstance string
param entraExternalIdDomain string
param entraExternalIdTenantId string
param entraExternalIdWebClientId string
param entraExternalIdApiClientId string
param entraExternalIdApiAudience string
param shoppingApiScope string
param sqlServerFullyQualifiedDomainName string
param sqlDatabaseName string
param storageBlobEndpoint string
param productImagesContainerName string
param productImagePublicBaseUri string
param productImageSasLifetimeMinutes int
param redisConnectionStringSecretUri string
param hasWebClientSecret bool
param webClientSecretUri string
param tags object

resource apiContainerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: apiContainerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${apiIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: containerRegistryLoginServer
          identity: apiIdentityResourceId
        }
      ]
      ingress: {
        external: false
        allowInsecure: false
        targetPort: 8080
        transport: 'auto'
      }
    }
    template: {
      containers: [
        {
          name: 'shopping-api'
          image: apiContainerImage
          resources: containerResources
          env: [
            {
              name: 'ASPNETCORE_HTTP_PORTS'
              value: '8080'
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: aspNetCoreEnvironment
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: apiIdentityClientId
            }
            {
              name: 'EntraExternalId__Instance'
              value: entraExternalIdInstance
            }
            {
              name: 'EntraExternalId__TenantId'
              value: entraExternalIdTenantId
            }
            {
              name: 'EntraExternalId__ClientId'
              value: entraExternalIdApiClientId
            }
            {
              name: 'EntraExternalId__Audience'
              value: entraExternalIdApiAudience
            }
            {
              name: 'ConnectionStrings__ShoppingDatabase'
              value: 'Server=tcp:${sqlServerFullyQualifiedDomainName},1433;Database=${sqlDatabaseName};Authentication=Active Directory Managed Identity;User Id=${apiIdentityClientId};Encrypt=True;TrustServerCertificate=False;'
            }
            {
              name: 'ProductImageStorage__ServiceUri'
              value: storageBlobEndpoint
            }
            {
              name: 'ProductImageStorage__ContainerName'
              value: productImagesContainerName
            }
            {
              name: 'ProductImageStorage__PublicBaseUri'
              value: productImagePublicBaseUri
            }
            {
              name: 'ProductImageStorage__UseSharedAccessSignatures'
              value: 'true'
            }
            {
              name: 'ProductImageStorage__SharedAccessSignatureLifetimeMinutes'
              value: string(productImageSasLifetimeMinutes)
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerAppMinReplicas
        maxReplicas: containerAppMaxReplicas
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

resource webContainerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: webContainerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${webIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: containerRegistryLoginServer
          identity: webIdentityResourceId
        }
      ]
      secrets: concat([
        {
          name: 'redis-connection-string'
          keyVaultUrl: redisConnectionStringSecretUri
          identity: webIdentityResourceId
        }
      ], hasWebClientSecret ? [
        {
          name: 'entra-client-secret'
          keyVaultUrl: webClientSecretUri
          identity: webIdentityResourceId
        }
      ] : [])
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8080
        transport: 'auto'
        stickySessions: {
          affinity: 'sticky'
        }
      }
    }
    template: {
      containers: [
        {
          name: 'shopping-web'
          image: webContainerImage
          resources: containerResources
          env: concat([
            {
              name: 'ASPNETCORE_HTTP_PORTS'
              value: '8080'
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: aspNetCoreEnvironment
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'EntraExternalId__Instance'
              value: entraExternalIdInstance
            }
            {
              name: 'EntraExternalId__Domain'
              value: entraExternalIdDomain
            }
            {
              name: 'EntraExternalId__TenantId'
              value: entraExternalIdTenantId
            }
            {
              name: 'EntraExternalId__ClientId'
              value: entraExternalIdWebClientId
            }
            {
              name: 'ShoppingApi__BaseUrl'
              value: 'https://${apiContainerApp.properties.configuration.ingress.fqdn}/'
            }
            {
              name: 'ShoppingApi__Scopes__0'
              value: shoppingApiScope
            }
            {
              name: 'ProductImageStorage__PublicBaseUri'
              value: productImagePublicBaseUri
            }
            {
              name: 'ShoppingAzure__Redis__ConnectionString'
              secretRef: 'redis-connection-string'
            }
          ], hasWebClientSecret ? [
            {
              name: 'EntraExternalId__ClientSecret'
              secretRef: 'entra-client-secret'
            }
          ] : [])
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerAppMinReplicas
        maxReplicas: containerAppMaxReplicas
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output webContainerAppName string = webContainerApp.name
output webContainerAppFqdn string = webContainerApp.properties.configuration.ingress.fqdn
output webRedirectUri string = 'https://${webContainerApp.properties.configuration.ingress.fqdn}/signin-oidc'
output apiContainerAppName string = apiContainerApp.name
