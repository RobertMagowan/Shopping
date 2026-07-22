using '../main.bicep'

param workloadName = readEnvironmentVariable('WORKLOAD_NAME', 'shopping')
param deploymentInstance = readEnvironmentVariable('DEPLOYMENT_INSTANCE', 'validation')
param environmentName = 'test'
param location = readEnvironmentVariable('AZURE_LOCATION', 'uksouth')
param resourceSuffix = readEnvironmentVariable('RESOURCE_SUFFIX', 'valtest')
param sqlAdministratorLogin = readEnvironmentVariable('SQL_ADMINISTRATOR_LOGIN', 'sqladminuser')
param sqlAdministratorPassword = readEnvironmentVariable('SQL_ADMINISTRATOR_PASSWORD', 'ReplaceOnlyForValidation123!')
param deploymentPrincipalObjectId = readEnvironmentVariable('AZURE_PRINCIPAL_OBJECT_ID', '00000000-0000-0000-0000-000000000000')
param enablePrivateEndpoints = false
param containerAppMinReplicas = 1
param containerAppMaxReplicas = 1
param containerAppCpu = '0.5'
param containerAppMemory = '1Gi'
param containerRegistrySkuName = 'Basic'
param containerImageTag = readEnvironmentVariable('CONTAINER_IMAGE_TAG', 'bootstrap')
param sqlDatabaseSkuName = 'Basic'
param sqlZoneRedundant = readEnvironmentVariable('SQL_ZONE_REDUNDANT', 'false') == 'true'
param managedRedisSkuName = 'Balanced_B0'
param managedRedisLocation = readEnvironmentVariable('MANAGED_REDIS_LOCATION', 'uksouth')
param enableFrontDoorImageDelivery = false
param productImageSasLifetimeMinutes = 10
param entraExternalIdInstance = readEnvironmentVariable('ENTRA_EXTERNAL_ID_INSTANCE', '')
param entraExternalIdDomain = readEnvironmentVariable('ENTRA_EXTERNAL_ID_DOMAIN', '')
param entraExternalIdTenantId = readEnvironmentVariable('ENTRA_EXTERNAL_ID_TENANT_ID', '')
param entraExternalIdWebClientId = readEnvironmentVariable('ENTRA_EXTERNAL_ID_WEB_CLIENT_ID', '')
param entraExternalIdWebClientSecret = readEnvironmentVariable('ENTRA_EXTERNAL_ID_WEB_CLIENT_SECRET', '')
param entraExternalIdApiClientId = readEnvironmentVariable('ENTRA_EXTERNAL_ID_API_CLIENT_ID', '')
param entraExternalIdApiAudience = readEnvironmentVariable('ENTRA_EXTERNAL_ID_API_AUDIENCE', '')
param shoppingApiScope = readEnvironmentVariable('SHOPPING_API_SCOPE', '')
