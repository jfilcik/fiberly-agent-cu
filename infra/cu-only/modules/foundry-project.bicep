@description('Name of the Foundry project (child of the AI Services resource).')
param name string

@description('Parent AI Services resource name (ARM type `Microsoft.CognitiveServices/accounts`).')
param accountName string

@description('Azure region for the project. Should match the parent resource region.')
param location string

@description('Tags applied to the project.')
param tags object = {}

@description('Display name for the project.')
param displayName string = name

@description('Optional project description.')
param projectDescription string = 'Foundry project for the Fibey CU demo.'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2024-10-01' = {
  parent: account
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: displayName
    description: projectDescription
  }
}

@description('Resource ID of the project.')
output id string = project.id

@description('Project name.')
output name string = project.name

@description('Project endpoint used by Foundry-aware SDKs and the agent runtime.')
output endpoint string = 'https://${accountName}.services.ai.azure.com/api/projects/${name}'

@description('Principal ID of the project managed identity (used for KB connections).')
output principalId string = project.identity.principalId
