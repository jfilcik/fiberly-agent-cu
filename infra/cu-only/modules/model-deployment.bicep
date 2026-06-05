@description('Name of the chat model deployment (consumed by the agent at runtime).')
param name string

@description('Parent AI Services resource name (ARM type `Microsoft.CognitiveServices/accounts`).')
param accountName string

@description('OpenAI model name (e.g. gpt-4.1-mini, gpt-4.1).')
param modelName string = 'gpt-4.1-mini'

@description('Model version. Leave blank to let Azure pick the default.')
param modelVersion string = '2025-04-14'

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
