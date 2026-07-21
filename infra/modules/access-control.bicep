targetScope = 'resourceGroup'

param containerRegistryName string
param storageAccountName string
param keyVaultName string
param deploymentPrincipalObjectId string
param webIdentityResourceId string
param webIdentityPrincipalId string
param apiIdentityResourceId string
param apiIdentityPrincipalId string

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource blobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}

resource acrPullRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

resource acrPushRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '8311e382-0749-4cb8-b61a-304f252e45ec'
}

resource blobDelegatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'
}

resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource deploymentAcrPushAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, deploymentPrincipalObjectId, acrPushRole.id)
  scope: containerRegistry
  properties: {
    principalId: deploymentPrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPushRole.id
  }
}

resource webAcrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, webIdentityResourceId, acrPullRole.id)
  scope: containerRegistry
  properties: {
    principalId: webIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRole.id
  }
}

resource apiAcrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, apiIdentityResourceId, acrPullRole.id)
  scope: containerRegistry
  properties: {
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRole.id
  }
}

resource apiBlobContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, apiIdentityResourceId, blobDataContributorRole.id)
  scope: storageAccount
  properties: {
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: blobDataContributorRole.id
  }
}

resource apiBlobDelegatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, apiIdentityResourceId, blobDelegatorRole.id)
  scope: storageAccount
  properties: {
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: blobDelegatorRole.id
  }
}

resource webKeyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, webIdentityResourceId, keyVaultSecretsUserRole.id)
  scope: keyVault
  properties: {
    principalId: webIdentityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRole.id
  }
}
