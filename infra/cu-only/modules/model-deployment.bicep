@description('Name of the chat model deployment (consumed by the agent at runtime).')
param name string

@description('Parent AI Services account name.')
param accountName string

@description('OpenAI model name (e.g. gpt-4o-mini, gpt-4o).')
param modelName string = 'gpt-4o-mini'

@description('Model version. Leave blank to let Azure pick the default.')
param modelVersion string = '2024-07-18'

@description('Deployment SKU name.')
param skuName string = 'GlobalStandard'

@description('SKU capacity (TPM in thousands for GlobalStandard, units for Standard).')
param skuCapacity int = 50

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: name
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

@description('Deployment name (use as FOUNDRY_MODEL / AZURE_AI_MODEL_DEPLOYMENT_NAME).')
output name string = deployment.name
