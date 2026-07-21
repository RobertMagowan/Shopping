targetScope = 'resourceGroup'

param location string
param enablePrivateEndpoints bool
param virtualNetworkName string
param containerAppsNetworkSecurityGroupName string
param natGatewayName string
param natPublicIpName string
param containerAppsInfrastructureSubnetName string
param privateEndpointSubnetName string
param appGatewaySubnetName string
param apimSubnetName string
param tags object

resource containerAppsNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: containerAppsNetworkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (enablePrivateEndpoints) {
  name: natPublicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource outboundNatGateway 'Microsoft.Network/natGateways@2024-05-01' = if (enablePrivateEndpoints) {
  name: natGatewayName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: '10.40.0.0/24'
        }
      }
      {
        name: apimSubnetName
        properties: {
          addressPrefix: '10.40.1.0/24'
        }
      }
      {
        name: containerAppsInfrastructureSubnetName
        properties: union({
          addressPrefix: '10.40.2.0/24'
          networkSecurityGroup: {
            id: containerAppsNetworkSecurityGroup.id
          }
          delegations: [
            {
              name: 'container-apps-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }, enablePrivateEndpoints ? {
          natGateway: {
            id: outboundNatGateway.id
          }
        } : {})
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.40.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource containerAppsInfrastructureSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: containerAppsInfrastructureSubnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: privateEndpointSubnetName
}

output virtualNetworkId string = virtualNetwork.id
output virtualNetworkName string = virtualNetwork.name
output containerAppsInfrastructureSubnetId string = containerAppsInfrastructureSubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
