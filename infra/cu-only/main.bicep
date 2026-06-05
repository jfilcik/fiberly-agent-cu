// CU demo greenfield infra: provisions the minimum cloud resources for
// Demos 1 + 2 (Foundry agent + CU). Two separate AIServices resources so
// CU can live in a CU-supported region even when the agent's Foundry
// resource does not (e.g. agent in westus3, CU in westus2).
//
//   foundryAgentResource — kind=AIServices in `agentLocation`. Has 1
//                          project + agent chat model deployment. This is
//                          the FOUNDRY_PROJECT_ENDPOINT for the agent.
//
//   cuResource           — optional separate AIServices resource in
//                          `cuLocation`. Used only when `agentLocation` is
//                          not CU-supported or differs from `cuLocation`.
//                          Hosts CU chat + embedding deployments for custom
//                          analyzer workflows.
//                          This is the AZURE_CONTENTUNDERSTANDING_ENDPOINT.
//
// CU supported regions: see
//   https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/language-region-support
// Pick a CU-supported region for `cuLocation`. `agentLocation` only needs
// to support your chosen chat model.
//
// For Demo 3 (Foundry IQ KB) layer `infra/main.bicep` on top with
// `includeFoundryIq=true`.

@description('Unique environment name used for resource naming.')
param environmentName string

@description('Default Azure region. Used as the default for both agent and CU resources unless overridden.')
param location string = resourceGroup().location

@description('Region for the Foundry resource that hosts the agent project + chat model deployment. Defaults to `location`. Must support your chosen chat model.')
param agentLocation string = location

// Keep this list aligned with current CU-supported regions:
// https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/language-region-support
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'japaneast'
  'koreacentral'
  'norwayeast'
  'polandcentral'
  'qatarcentral'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus'
  'westus2'
])
@description('Region for the CU AIServices resource. Defaults to `location`. MUST be one of the CU-supported regions (see https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/language-region-support). If your `agentLocation` is not CU-supported, set this to a different region.')
param cuLocation string = location

@description('Tags applied to all resources.')
param tags object = {
  'azd-env-name': environmentName
  'cu-demo': 'cu-only'
}

@description('Chat model deployment name used at runtime. Lowercase, hyphen-separated.')
param chatModelDeploymentName string = 'gpt-4.1-mini'

@description('CU chat model deployment name used by CU custom analyzer workflows.')
param cuChatModelDeploymentName string = 'gpt-4.1-mini-cu'

@description('OpenAI model name to deploy on the Foundry agent resource.')
param chatModelName string = 'gpt-4.1-mini'

@description('OpenAI chat model version to deploy.')
param chatModelVersion string = '2025-04-14'

@description('Embedding model deployment name used by CU custom analyzers.')
param embeddingModelDeploymentName string = 'text-embedding-3-large'

@description('Embedding model name to deploy on the Foundry agent resource.')
param embeddingModelName string = 'text-embedding-3-large'

@description('Embedding model version to deploy.')
param embeddingModelVersion string = '1'

@description('Foundry project name (child of the agent AI Services resource).')
param foundryProjectName string = 'fibey'

var resourceToken = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName))
var sanitizedEnvironmentName = replace(toLower(environmentName), '-', '')
var normalizedAgentLocation = toLower(agentLocation)
var normalizedCuLocation = toLower(cuLocation)

// Keep this list aligned with current CU-supported regions.
var cuSupportedRegions = [
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'japaneast'
  'koreacentral'
  'norwayeast'
  'polandcentral'
  'qatarcentral'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'uaenorth'
  'uksouth'
  'westeurope'
  'westus'
  'westus2'
]
var isAgentLocationCuSupported = contains(cuSupportedRegions, normalizedAgentLocation)
var deploySeparateCuResource = !isAgentLocationCuSupported || normalizedCuLocation != normalizedAgentLocation

// Distinct names so the two resources don't collide on the globally-unique custom subdomain.
var foundryAgentResourceName = 'aifagent${take(sanitizedEnvironmentName, 8)}${take(resourceToken, 6)}'
var cuResourceName           = 'aifcu${take(sanitizedEnvironmentName, 10)}${take(resourceToken, 6)}'

// ── Foundry agent resource: resource + project + agent chat deployment ───────
module foundryAgentResource 'modules/foundry-account.bicep' = {
  name: 'foundry-agent-account'
  params: {
    name: foundryAgentResourceName
    location: agentLocation
    tags: tags
  }
}

module foundryProject 'modules/foundry-project.bicep' = {
  name: 'foundry-project'
  params: {
    name: foundryProjectName
    accountName: foundryAgentResource.outputs.name
    location: agentLocation
    tags: tags
  }
}

module agentChatModel 'modules/model-deployment.bicep' = {
  name: 'agent-chat-model'
  params: {
    name: chatModelDeploymentName
    accountName: foundryAgentResource.outputs.name
    modelName: chatModelName
    modelVersion: chatModelVersion
  }
}

// ── CU resource: conditional. Reuse agent resource when possible. ────────────
module cuResource 'modules/foundry-account.bicep' = if (deploySeparateCuResource) {
  name: 'cu-account'
  params: {
    name: cuResourceName
    location: cuLocation
    tags: tags
  }
}

module cuChatModel 'modules/model-deployment.bicep' = {
  name: 'cu-chat-model'
  params: {
    name: cuChatModelDeploymentName
    accountName: deploySeparateCuResource ? cuResource!.outputs.name : foundryAgentResource.outputs.name
    modelName: chatModelName
    modelVersion: chatModelVersion
  }
}

module embeddingModelOnAgent 'modules/model-deployment.bicep' = if (!deploySeparateCuResource) {
  name: 'embedding-model-on-agent'
  params: {
    name: embeddingModelDeploymentName
    accountName: foundryAgentResource.outputs.name
    modelName: embeddingModelName
    modelVersion: embeddingModelVersion
  }
}

module embeddingModelOnCu 'modules/model-deployment.bicep' = if (deploySeparateCuResource) {
  name: 'embedding-model-on-cu'
  params: {
    name: embeddingModelDeploymentName
    accountName: cuResource!.outputs.name
    modelName: embeddingModelName
    modelVersion: embeddingModelVersion
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

@description('Foundry agent AI Services resource name.')
output foundryAccountName string = foundryAgentResource.outputs.name

@description('Foundry project endpoint. Set as FOUNDRY_PROJECT_ENDPOINT in .env.')
output foundryProjectEndpoint string = foundryProject.outputs.endpoint

@description('CU AI Services resource name (separate from the Foundry agent resource).')
output cuAccountName string = deploySeparateCuResource ? cuResource!.outputs.name : foundryAgentResource.outputs.name

@description('CU data-plane endpoint. Set as AZURE_CONTENTUNDERSTANDING_ENDPOINT in .env. Can point to the same resource as the Foundry agent if both regions match, but defaults to the dedicated CU resource in `cuLocation`.')
output contentUnderstandingEndpoint string = deploySeparateCuResource ? cuResource!.outputs.contentUnderstandingEndpoint : foundryAgentResource.outputs.contentUnderstandingEndpoint

@description('Chat model deployment name. Set as FOUNDRY_MODEL and AZURE_AI_MODEL_DEPLOYMENT_NAME in .env.')
output chatModelDeploymentName string = agentChatModel.outputs.name

@description('CU chat deployment name used for CU analyzer workflows.')
output cuChatModelDeploymentName string = cuChatModel.outputs.name

@description('Embedding model deployment name for CU custom analyzer creation (for example TEXT_EMBEDDING_3_LARGE_DEPLOYMENT).')
output embeddingModelDeploymentName string = deploySeparateCuResource ? embeddingModelOnCu!.outputs.name : embeddingModelOnAgent!.outputs.name

@description('Resource ID of the Foundry agent resource (used by sample-setup-cu for role assignment guidance).')
output foundryAccountId string = foundryAgentResource.outputs.id

@description('Resource ID of the Foundry project.')
output foundryProjectId string = foundryProject.outputs.id

@description('Resource ID of the CU resource (used by sample-setup-cu for role assignment guidance).')
output cuAccountId string = deploySeparateCuResource ? cuResource!.outputs.id : foundryAgentResource.outputs.id

