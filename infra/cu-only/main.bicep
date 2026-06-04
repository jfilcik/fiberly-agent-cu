// CU-only infra: the minimum needed for sample-demo-cu Demos 1 + 2.
// Provisions a Foundry (AI Services) account, one project, and one chat model deployment.
// No Storage, no Search, no Container Apps. For Demo 3 (Foundry IQ KB), layer
// infra/main.bicep on top with includeFoundryIq=true.

@description('Unique environment name used for resource naming.')
param environmentName string

@description('Azure region for all resources. Must be CU-supported (e.g. eastus, westus2, swedencentral).')
param location string = resourceGroup().location

@description('Tags applied to all resources.')
param tags object = {
  'azd-env-name': environmentName
  'cu-demo': 'cu-only'
}

@description('Chat model deployment name used at runtime. Lowercase, hyphen-separated.')
param chatModelDeploymentName string = 'gpt-4o-mini'

@description('OpenAI model name to deploy.')
param chatModelName string = 'gpt-4o-mini'

@description('OpenAI model version to deploy.')
param chatModelVersion string = '2024-07-18'

@description('Foundry project name (child of the AI Services account).')
param foundryProjectName string = 'fibey'

var resourceToken = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName))
var sanitizedEnvironmentName = replace(toLower(environmentName), '-', '')
var foundryAccountName = 'aif${take(sanitizedEnvironmentName, 12)}${take(resourceToken, 6)}'

module foundryAccount 'modules/foundry-account.bicep' = {
  name: 'foundry-account'
  params: {
    name: foundryAccountName
    location: location
    tags: tags
  }
}

module foundryProject 'modules/foundry-project.bicep' = {
  name: 'foundry-project'
  params: {
    name: foundryProjectName
    accountName: foundryAccount.outputs.name
    location: location
    tags: tags
  }
}

module chatModel 'modules/model-deployment.bicep' = {
  name: 'chat-model'
  params: {
    name: chatModelDeploymentName
    accountName: foundryAccount.outputs.name
    modelName: chatModelName
    modelVersion: chatModelVersion
  }
}

@description('Foundry (AI Services) account name.')
output foundryAccountName string = foundryAccount.outputs.name

@description('Foundry project endpoint. Set as FOUNDRY_PROJECT_ENDPOINT in .env.')
output foundryProjectEndpoint string = foundryProject.outputs.endpoint

@description('CU data-plane endpoint. Set as AZURE_CONTENTUNDERSTANDING_ENDPOINT in .env.')
output contentUnderstandingEndpoint string = foundryAccount.outputs.contentUnderstandingEndpoint

@description('Chat model deployment name. Set as FOUNDRY_MODEL and AZURE_AI_MODEL_DEPLOYMENT_NAME in .env.')
output chatModelDeploymentName string = chatModel.outputs.name

@description('Resource ID of the Foundry account (used by sample-setup-cu for role assignment guidance).')
output foundryAccountId string = foundryAccount.outputs.id

@description('Resource ID of the Foundry project.')
output foundryProjectId string = foundryProject.outputs.id
