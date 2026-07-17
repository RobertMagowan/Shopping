using '../main.bicep'

param workloadName = readEnvironmentVariable('WORKLOAD_NAME', 'shopping')
param deploymentInstance = readEnvironmentVariable('DEPLOYMENT_INSTANCE', 'validation')
param environmentName = 'prod'
param location = readEnvironmentVariable('AZURE_LOCATION', 'uksouth')
param resourceSuffix = readEnvironmentVariable('RESOURCE_SUFFIX', 'valprod')
param sqlAdministratorLogin = readEnvironmentVariable('SQL_ADMINISTRATOR_LOGIN', 'sqladminuser')
param sqlAdministratorPassword = readEnvironmentVariable('SQL_ADMINISTRATOR_PASSWORD', 'ReplaceOnlyForValidation123!')
param enablePrivateEndpoints = true
param allowPublicAppAccess = false
param appServicePlanSkuName = 'P1v3'
param sqlDatabaseSkuName = 'S1'
param redisSkuName = 'Standard'
param redisSkuFamily = 'C'
param redisSkuCapacity = 1
param enableFrontDoorImageDelivery = true
param productImageSasLifetimeMinutes = 10
param entraExternalIdInstance = readEnvironmentVariable('ENTRA_EXTERNAL_ID_INSTANCE', '')
param entraExternalIdDomain = readEnvironmentVariable('ENTRA_EXTERNAL_ID_DOMAIN', '')
param entraExternalIdTenantId = readEnvironmentVariable('ENTRA_EXTERNAL_ID_TENANT_ID', '')
param entraExternalIdWebClientId = readEnvironmentVariable('ENTRA_EXTERNAL_ID_WEB_CLIENT_ID', '')
param entraExternalIdWebClientSecret = readEnvironmentVariable('ENTRA_EXTERNAL_ID_WEB_CLIENT_SECRET', '')
param entraExternalIdApiClientId = readEnvironmentVariable('ENTRA_EXTERNAL_ID_API_CLIENT_ID', '')
param entraExternalIdApiAudience = readEnvironmentVariable('ENTRA_EXTERNAL_ID_API_AUDIENCE', '')
param shoppingApiScope = readEnvironmentVariable('SHOPPING_API_SCOPE', '')
