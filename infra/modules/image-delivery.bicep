targetScope = 'resourceGroup'

param enableFrontDoorImageDelivery bool
param location string
param frontDoorProfileName string
param frontDoorEndpointName string
param frontDoorOriginGroupName string
param frontDoorOriginName string
param frontDoorRouteName string
param storageAccountName string
param storageAccountId string
param storageBlobEndpoint string
param productImagesContainerName string
param tags object

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-05-01' = if (enableFrontDoorImageDelivery) {
  name: frontDoorProfileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-05-01' = if (enableFrontDoorImageDelivery) {
  parent: frontDoorProfile
  name: frontDoorEndpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-05-01' = if (enableFrontDoorImageDelivery) {
  parent: frontDoorProfile
  name: frontDoorOriginGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

resource frontDoorOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-05-01' = if (enableFrontDoorImageDelivery) {
  parent: frontDoorOriginGroup
  name: frontDoorOriginName
  properties: {
    hostName: '${storageAccountName}.blob.${environment().suffixes.storage}'
    originHostHeader: '${storageAccountName}.blob.${environment().suffixes.storage}'
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    privateLinkResourceId: storageAccountId
    privateLinkLocation: location
    privateLinkSubResourceType: 'blob'
  }
}

resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-05-01' = if (enableFrontDoorImageDelivery) {
  parent: frontDoorEndpoint
  name: frontDoorRouteName
  dependsOn: [
    frontDoorOrigin
  ]
  properties: {
    enabledState: 'Enabled'
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    originPath: '/${productImagesContainerName}'
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'UseQueryString'
      compressionSettings: {
        isCompressionEnabled: false
      }
    }
  }
}

var frontDoorImageEndpoint = enableFrontDoorImageDelivery ? 'https://${frontDoorEndpoint!.properties.hostName}' : ''

output frontDoorImageEndpoint string = frontDoorImageEndpoint
output productImagePublicBaseUri string = enableFrontDoorImageDelivery ? frontDoorImageEndpoint : '${storageBlobEndpoint}/${productImagesContainerName}'
