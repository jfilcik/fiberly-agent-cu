// CU demo greenfield infra: provisions the minimum cloud resources for
// Demos 1 + 2 (Foundry agent + CU). Two separate AIServices accounts so
// CU can live in a CU-supported region even when the agent's Foundry
// account does not (e.g. agent in westus3, CU in westus2).
//
//   foundryAgentAccount  — kind=AIServices in `agentLocation`. Has 1
//                          project + 1 chat model deployment. This is
//                          the FOUNDRY_PROJECT_ENDPOINT for the agent.
//
//   cuAccount            — kind=AIServices in `cuLocation`. NO project,
//                          NO model deployment. CU is an account-level
//                          data-plane service so it doesn't need either.
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

@description('Default Azure region. Used as the default for both agent and CU accounts unless overridden.')
param location string = resourceGroup().location

@description('Region for the Foundry account that hosts the agent project + chat model deployment. Defaults to `location`. Must support your chosen chat model.')
param agentLocation string = location

@description('Region for the CU AIServices account. Defaults to `location`. MUST be one of the CU-supported regions (see https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/language-region-support). If your `agentLocation` is not CU-supported, set this to a different region.')
param cuLocation string = location

@description('Tags applied to all resources.')
param tags object = {
  'azd-env-name': environmentName
  'cu-demo': 'cu-only'
}

@description('Chat model deployment name used at runtime. Lowercase, hyphen-separated.')
param chatModelDeploymentName string = 'gpt-4o-mini'

@description('OpenAI model name to deploy on the Foundry agent account.')
param chatModelName string = 'gpt-4o-mini'

@description('OpenAI model version to deploy.')
param chatModelVersion string = '2024-07-18'

@description('Foundry project name (child of the agent AI Services account).')
param foundryProjectName string = 'fibey'

var resourceToken = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, environmentName))
var sanitizedEnvironmentName = replace(toLower(environmentName), '-', '')

// Distinct names so the two accounts don't collide on the globally-unique custom subdomain.
var foundryAgentAccountName = 'aifagent${take(sanitizedEnvironmentName, 8)}${take(resourceToken, 6)}'
var cuAccountName           = 'aifcu${take(sanitizedEnvironmentName, 10)}${take(resourceToken, 6)}'

// ── Foundry agent account: account + project + 1 chat model ───────────────
module foundryAgentAccount 'modules/foundry-account.bicep' = {
  name: 'foundry-agent-account'
  params: {
    name: foundryAgentAccountName
    location: agentLocation
    tags: tags
  }
}

module foundryProject 'modules/foundry-project.bicep' = {
  name: 'foundry-project'
  params: {
    name: foundryProjectName
    accountName: foundryAgentAccount.outputs.name
    location: agentLocation
    tags: tags
  }
}

module chatModel 'modules/model-deployment.bicep' = {
  name: 'chat-model'
  params: {
    name: chatModelDeploymentName
    accountName: foundryAgentAccount.outputs.name
    modelName: chatModelName
    modelVersion: chatModelVersion
  }
}

// ── CU account: just the AIServices account, in a CU-supported region ─────
// Intentionally no project and no model deployment. CU analyze is
// account-level data plane — needs neither.
module cuAccount 'modules/foundry-account.bicep' = {
  name: 'cu-account'
  params: {
    name: cuAccountName
    location: cuLocation
    tags: tags
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

@description('Foundry agent (AI Services) account name.')
output foundryAccountName string = foundryAgentAccount.outputs.name

@description('Foundry project endpoint. Set as FOUNDRY_PROJECT_ENDPOINT in .env.')
output foundryProjectEndpoint string = foundryProject.outputs.endpoint

@description('CU AIServices account name (separate from the Foundry agent account).')
output cuAccountName string = cuAccount.outputs.name

@description('CU data-plane endpoint. Set as AZURE_CONTENTUNDERSTANDING_ENDPOINT in .env. Can point to the same account as the Foundry agent if both regions match, but defaults to the dedicated CU account in `cuLocation`.')
output contentUnderstandingEndpoint string = cuAccount.outputs.contentUnderstandingEndpoint

@description('Chat model deployment name. Set as FOUNDRY_MODEL and AZURE_AI_MODEL_DEPLOYMENT_NAME in .env.')
output chatModelDeploymentName string = chatModel.outputs.name

@description('Resource ID of the Foundry agent account (used by sample-setup-cu for role assignment guidance).')
output foundryAccountId string = foundryAgentAccount.outputs.id

@description('Resource ID of the Foundry project.')
output foundryProjectId string = foundryProject.outputs.id

@description('Resource ID of the CU account (used by sample-setup-cu for role assignment guidance).')
output cuAccountId string = cuAccount.outputs.id

