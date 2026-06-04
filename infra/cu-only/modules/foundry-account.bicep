@description('Name of the Foundry (AI Services) account.')
param name string

@description('Azure region. Must be a region that supports both Foundry and Content Understanding.')
param location string

@description('Tags applied to the account.')
param tags object = {}

@description('SKU for the AI Services account.')
param sku string = 'S0'

@description('Custom subdomain for the AI Services account. Defaults to the account name (must be globally unique).')
param customSubDomainName string = name

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

@description('Resource ID of the AI Services (Foundry) account.')
output id string = account.id

@description('Name of the AI Services account.')
output name string = account.name

@description('Default endpoint used by both Foundry and CU data planes (services.ai.azure.com host).')
output endpoint string = 'https://${customSubDomainName}.services.ai.azure.com/'

@description('CU-specific data-plane endpoint (same host, different path scope).')
output contentUnderstandingEndpoint string = 'https://${customSubDomainName}.services.ai.azure.com/'

@description('Principal ID of the account managed identity.')
output principalId string = account.identity.principalId
