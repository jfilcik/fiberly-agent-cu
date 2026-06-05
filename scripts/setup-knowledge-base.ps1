#Requires -Version 5.1
<#
.SYNOPSIS
    Upload FoundryIQ docs to blob storage and configure the full AI Search +
    FoundryIQ pipeline. PowerShell sibling of setup-knowledge-base.sh.

.DESCRIPTION
    Pure Windows-native — no Git Bash / WSL required. Uses Invoke-RestMethod,
    ConvertFrom-Json, and az CLI exclusively. Same flag contract as the .sh
    sibling so SKILL.md instructions stay identical.

    Dev path (default and --cu-demo): uses data-plane auth (Storage MI via
    --auth-mode login, Search via AAD Bearer token). Does NOT touch listKeys,
    admin-key, or role assignments.

    Admin path (--admin-prep): performs the one-time Foundry MI ->
    Search Index Data Reader role assignment.

.PARAMETER FoundryProjectEndpoint
    https://<account>.services.ai.azure.com/api/projects/<project>
    Can also be passed via the FOUNDRY_PROJECT_ENDPOINT env var.

.PARAMETER CuDemo
    Set up minimal + standard KB pair for Foundry IQ CU ingestion comparison.

.PARAMETER AdminPrep
    Admin mode: assign Search Index Data Reader to the Foundry MI on the
    Search service. Requires User Access Administrator.
#>
param(
    [Parameter(Position = 0)]
    [string]$FoundryProjectEndpoint = $env:FOUNDRY_PROJECT_ENDPOINT,

    [switch]$CuDemo,
    [switch]$AdminPrep,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# ─── Paths & constants ────────────────────────────────────────────────
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptDir
$DocsDir     = Join-Path $RepoRoot 'services/foundry-iq-docs/docs'
$CuDocsDir   = Join-Path $RepoRoot 'services/foundry-iq-docs/content-understanding/docs'
$EnvFile     = Join-Path $RepoRoot '.env'
$EnvExample  = Join-Path $RepoRoot '.env.example'

$ContainerName   = 'foundry-iq-docs'
$IndexName       = 'foundry-iq-docs-index'
$DatasourceName  = 'foundry-iq-docs-ds'
$IndexerName     = 'foundry-iq-docs-indexer'
$KbName          = 'fibey-field-ops-kb'
$KsName          = 'fibey-field-ops-ks'
$ConnectionName  = 'kb-fibey-field-ops-kb'

$SearchApiVersion             = '2024-07-01'
$KnowledgeApiVersion          = '2026-04-01'
$FoundryConnectionApiVersion  = '2025-10-01-preview'
$SearchIndexDataReaderRoleId  = '1407120a-92aa-4202-b7e9-c0e197c71c8f'

# ─── Help ─────────────────────────────────────────────────────────────
if ($Help) {
    @"
Usage:
  ./scripts/setup-knowledge-base.ps1 [-FoundryProjectEndpoint <url>]
  ./scripts/setup-knowledge-base.ps1 -CuDemo [-FoundryProjectEndpoint <url>]
  ./scripts/setup-knowledge-base.ps1 -AdminPrep [-FoundryProjectEndpoint <url>]

Modes:
  default      Dev path: create datasource/index/indexer/KS/KB/Foundry-connection using data-plane RBAC.
  -CuDemo      Dev path for the CU demo: create minimal + standard KS/KB pair.
  -AdminPrep   Admin path: assign Search Index Data Reader to the Foundry MI.

Required env var (or -FoundryProjectEndpoint arg):
  FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>

Required dev-track roles:
  - Storage Blob Data Contributor      on the storage account
  - Search Index Data Contributor      on the Search service
  - Azure AI User                       on the Foundry project
  - Reader                              on the resource group (recommended; data-plane roles imply per-resource read)

Required admin-track roles (-AdminPrep mode):
  - User Access Administrator           on the Search service
"@ | Write-Host
    exit 0
}

# ─── Helpers ──────────────────────────────────────────────────────────
function Upsert-EnvVar {
    param([string]$Key, [string]$Value, [string]$FilePath)
    $line = "$Key=$Value"
    if (Test-Path $FilePath) {
        $content = Get-Content $FilePath -Raw
        $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
        if ($content -match $pattern) {
            $newContent = [regex]::Replace($content, $pattern, [System.Text.RegularExpressions.Regex]::Escape($line) -replace '\\(.)','$1')
            # Simpler: read lines, replace matching line
            $lines = Get-Content $FilePath
            $updated = $lines | ForEach-Object { if ($_ -match "^$([regex]::Escape($Key))=") { $line } else { $_ } }
            Set-Content -Path $FilePath -Value $updated -Encoding UTF8
        } else {
            Add-Content -Path $FilePath -Value "`n$line"
        }
    } else {
        Set-Content -Path $FilePath -Value $line -Encoding UTF8
    }
}

function Ensure-EnvFile {
    if (-not (Test-Path $EnvFile) -and (Test-Path $EnvExample)) {
        Copy-Item $EnvExample $EnvFile
        Write-Host "Created .env from .env.example"
    }
}

function Resolve-CuKeyFromEndpoint {
    param([string]$Endpoint)
    $normalized = $Endpoint.TrimEnd('/') + '/'
    $accountJson = az cognitiveservices account list `
        --query "[?properties.endpoint=='$normalized'] | [0] | {name:name,resourceGroup:resourceGroup}" `
        -o json 2>$null
    if (-not $accountJson -or $accountJson -eq 'null') { return $null }
    $account = $accountJson | ConvertFrom-Json
    if (-not $account.name -or -not $account.resourceGroup) { return $null }
    $key = az cognitiveservices account keys list `
        --name $account.name --resource-group $account.resourceGroup `
        --query key1 -o tsv 2>$null
    if (-not $key) { return $null }
    return $key
}

function Invoke-SearchRest {
    param(
        [string]$Method,
        [string]$Url,
        [string]$Body
    )
    $headers = @{
        'Authorization' = "Bearer $script:SearchToken"
        'Content-Type'  = 'application/json'
    }
    if ($Body) {
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -Body $Body
    } else {
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers
    }
}

function Remove-SearchResourceIfExists {
    param([string]$ResourceType, [string]$ResourceName, [string]$ApiVersion)
    $url = "$script:SearchEndpoint/$ResourceType/$($ResourceName)?api-version=$ApiVersion"
    try {
        Invoke-RestMethod -Method DELETE -Uri $url `
            -Headers @{ 'Authorization' = "Bearer $script:SearchToken" } | Out-Null
        Write-Host "  - Deleted $ResourceType/$ResourceName"
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 404) {
            Write-Host "  - $ResourceType/$ResourceName not found (skip)"
        } else {
            Write-Host "  - Failed deleting $ResourceType/$ResourceName (HTTP $code)"
            throw
        }
    }
}

function Remove-FoundryConnectionIfExists {
    param([string]$ConnectionName)
    $url = "https://management.azure.com$($script:FoundryProjectResourceId)/connections/$($ConnectionName)?api-version=$FoundryConnectionApiVersion"
    try {
        Invoke-RestMethod -Method DELETE -Uri $url `
            -Headers @{ 'Authorization' = "Bearer $script:ManagementToken" } | Out-Null
        Write-Host "  - Deleted Foundry connection $ConnectionName"
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 404) {
            Write-Host "  - Foundry connection $ConnectionName not found (skip)"
        } else {
            Write-Host "  - Failed deleting Foundry connection $ConnectionName (HTTP $code)"
            throw
        }
    }
}

# ─── Validate inputs ──────────────────────────────────────────────────
if (-not $env:AZURE_RESOURCE_GROUP) {
    Write-Error "AZURE_RESOURCE_GROUP must be set before running this script."
    exit 1
}
$AzureResourceGroup = $env:AZURE_RESOURCE_GROUP

if (-not $FoundryProjectEndpoint) {
    Write-Error "FOUNDRY_PROJECT_ENDPOINT must be set (env var) or passed as the first argument."
    exit 1
}
$FoundryProjectEndpoint = $FoundryProjectEndpoint.TrimEnd('/')

if ($FoundryProjectEndpoint -match '^https?://([^.]+)\.services\.ai\.azure\.com') {
    $FoundryAccountName = $Matches[1]
} else {
    Write-Error "Could not parse Foundry account from $FoundryProjectEndpoint"
    exit 1
}
if ($FoundryProjectEndpoint -match '/api/projects/([^/?#]+)') {
    $FoundryProjectName = $Matches[1]
} else {
    Write-Error "Could not parse Foundry project from $FoundryProjectEndpoint"
    exit 1
}

# ─── Resolve resource names from azd outputs ──────────────────────────
Write-Host "Reading azd outputs..."
$StorageAccount = (azd env get-value storageAccountName 2>$null)
if (-not $StorageAccount) {
    $StorageAccount = az storage account list -g $AzureResourceGroup --query "[0].name" -o tsv
}
$SearchService = (azd env get-value searchServiceName 2>$null)
if (-not $SearchService) {
    $SearchService = az search service list -g $AzureResourceGroup --query "[0].name" -o tsv
}
if (-not $StorageAccount -or -not $SearchService) {
    Write-Error "Could not resolve storage account or search service from azd outputs or Azure CLI."
    exit 1
}

$script:SearchEndpoint = "https://$SearchService.search.windows.net"

$script:SearchResourceId = az search service show `
    --name $SearchService --resource-group $AzureResourceGroup --query id -o tsv

$script:StorageResourceId = az storage account show `
    --name $StorageAccount --query id -o tsv

$script:SearchToken = az account get-access-token `
    --resource https://search.azure.com --query accessToken -o tsv
if (-not $script:SearchToken) {
    Write-Error @"
Failed to acquire Search data-plane AAD token.
Make sure your Search service has AAD auth enabled:
  az search service update -n $SearchService -g $AzureResourceGroup --auth-options aad
"@
    exit 1
}

$SubscriptionId = az account show --query id -o tsv

$script:FoundryProjectResourceId = az resource list `
    --query "[?(type=='Microsoft.CognitiveServices/accounts/projects' || type=='Microsoft.MachineLearningServices/workspaces/projects') && (contains(id, '/accounts/$FoundryAccountName/projects/$FoundryProjectName') || contains(id, '/workspaces/$FoundryAccountName/projects/$FoundryProjectName'))].id | [0]" `
    -o tsv

if (-not $script:FoundryProjectResourceId) {
    Write-Error "Could not resolve a Foundry project resource ID from FOUNDRY_PROJECT_ENDPOINT: $FoundryProjectEndpoint"
    exit 1
}

if ($script:FoundryProjectResourceId -match '/resourceGroups/([^/]+)/') {
    $FoundryResourceGroup = $Matches[1]
} else {
    Write-Error "Could not resolve Foundry resource group from project resource ID."
    exit 1
}

if ($script:FoundryProjectResourceId -like '*Microsoft.CognitiveServices/accounts*') {
    $FoundryAccountResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$FoundryResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryAccountName"
} else {
    $FoundryAccountResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$FoundryResourceGroup/providers/Microsoft.MachineLearningServices/workspaces/$FoundryAccountName"
}

$FoundryMiPrincipalId = az resource show `
    --ids $script:FoundryProjectResourceId `
    --api-version $FoundryConnectionApiVersion `
    --query identity.principalId -o tsv

if (-not $FoundryMiPrincipalId) {
    $FoundryMiPrincipalId = az resource show `
        --ids $FoundryAccountResourceId `
        --api-version $FoundryConnectionApiVersion `
        --query identity.principalId -o tsv
}

if (-not $FoundryMiPrincipalId) {
    Write-Error "Could not resolve the Foundry managed identity principal ID for RBAC assignment."
    exit 1
}

$RoleDefinitionId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$SearchIndexDataReaderRoleId"
$script:ManagementToken = az account get-access-token `
    --scope https://management.azure.com/.default --query accessToken -o tsv

$CuEndpoint = $env:AZURE_CONTENTUNDERSTANDING_ENDPOINT
$CuKey      = $env:AZURE_CONTENTUNDERSTANDING_KEY

if ($CuDemo -and $CuEndpoint -and -not $CuKey) {
    Write-Host "Attempting to resolve AZURE_CONTENTUNDERSTANDING_KEY from Azure (az login context)..."
    $resolved = Resolve-CuKeyFromEndpoint -Endpoint $CuEndpoint
    if ($resolved) {
        $CuKey = $resolved
        Write-Host "✓ Resolved CU key from AI Services account"
        Ensure-EnvFile
        if (Test-Path $EnvFile) {
            Upsert-EnvVar -Key 'AZURE_CONTENTUNDERSTANDING_ENDPOINT' -Value $CuEndpoint -FilePath $EnvFile
            Upsert-EnvVar -Key 'AZURE_CONTENTUNDERSTANDING_KEY' -Value $CuKey -FilePath $EnvFile
            Write-Host "✓ Updated AZURE_CONTENTUNDERSTANDING_ENDPOINT and AZURE_CONTENTUNDERSTANDING_KEY in .env"
        }
    } else {
        Write-Host "⚠ Could not auto-resolve AZURE_CONTENTUNDERSTANDING_KEY from endpoint: $CuEndpoint"
        Write-Host "  Provide AZURE_CONTENTUNDERSTANDING_KEY manually if standard mode needs key-based auth."
    }
}

Write-Host ""
Write-Host "Storage Account       : $StorageAccount"
Write-Host "Search Service        : $SearchService"
Write-Host "Search Endpoint       : $script:SearchEndpoint"
Write-Host "Foundry Endpoint      : $FoundryProjectEndpoint"
Write-Host "Foundry Resource Group: $FoundryResourceGroup"
Write-Host "Foundry Account       : $FoundryAccountName"
Write-Host "Foundry Project       : $FoundryProjectName"
if ($CuDemo) {
    Write-Host "CU Endpoint           : $(if ($CuEndpoint) { $CuEndpoint } else { '<not set — standard mode uses default AI services>' })"
}
Write-Host ""

# ─── CU Demo path ─────────────────────────────────────────────────────
if ($CuDemo) {
    $CuContainerName        = 'foundry-iq-cu-demo'
    $MinimalKsName          = 'fibey-iq-minimal-ks'
    $MinimalKbName          = 'fibey-iq-minimal-kb'
    $MinimalConnectionName  = 'kb-fibey-iq-minimal'
    $StandardKsName         = 'fibey-iq-standard-ks'
    $StandardKbName         = 'fibey-iq-standard-kb'
    $StandardConnectionName = 'kb-fibey-iq-standard'

    if (-not (Test-Path $DocsDir) -or @(Get-ChildItem $DocsDir -File -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Error "No base FoundryIQ docs found in $DocsDir"
        exit 1
    }
    if (-not (Test-Path $CuDocsDir) -or @(Get-ChildItem $CuDocsDir -File -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Error "No CU demo docs found in $CuDocsDir"
        exit 1
    }

    Write-Host ""
    Write-Host "=== Cleaning existing CU demo resources (if any) ==="
    Remove-FoundryConnectionIfExists -ConnectionName $MinimalConnectionName
    Remove-FoundryConnectionIfExists -ConnectionName $StandardConnectionName
    Remove-SearchResourceIfExists -ResourceType 'knowledgebases' -ResourceName $MinimalKbName -ApiVersion $KnowledgeApiVersion
    Remove-SearchResourceIfExists -ResourceType 'knowledgebases' -ResourceName $StandardKbName -ApiVersion $KnowledgeApiVersion
    Remove-SearchResourceIfExists -ResourceType 'knowledgesources' -ResourceName $MinimalKsName -ApiVersion $KnowledgeApiVersion
    Remove-SearchResourceIfExists -ResourceType 'knowledgesources' -ResourceName $StandardKsName -ApiVersion $KnowledgeApiVersion
    foreach ($ks in @($MinimalKsName, $StandardKsName)) {
        Remove-SearchResourceIfExists -ResourceType 'indexers'   -ResourceName "$ks-indexer"   -ApiVersion $SearchApiVersion
        Remove-SearchResourceIfExists -ResourceType 'skillsets'  -ResourceName "$ks-skillset"  -ApiVersion $SearchApiVersion
        Remove-SearchResourceIfExists -ResourceType 'indexes'    -ResourceName "$ks-index"     -ApiVersion $SearchApiVersion
        Remove-SearchResourceIfExists -ResourceType 'datasources' -ResourceName "$ks-datasource" -ApiVersion $SearchApiVersion
    }

    Write-Host ""
    Write-Host "=== Creating blob container: $CuContainerName ==="
    az storage container create `
        --name $CuContainerName `
        --account-name $StorageAccount `
        --auth-mode login `
        --only-show-errors | Out-Null
    Start-Sleep -Seconds 5

    Write-Host ""
    Write-Host "=== Uploading CU + base knowledge documents ==="
    az storage blob upload-batch `
        --source $DocsDir --destination $CuContainerName `
        --account-name $StorageAccount --auth-mode login `
        --overwrite --no-progress
    az storage blob upload-batch `
        --source $CuDocsDir --destination $CuContainerName `
        --account-name $StorageAccount --auth-mode login `
        --overwrite --no-progress

    $totalDocs = @(Get-ChildItem $DocsDir -File).Count + @(Get-ChildItem $CuDocsDir -File).Count
    Write-Host "✓ Uploaded $totalDocs document(s)"

    function New-CuKnowledgeSource {
        param([string]$Name, [string]$ExtractionMode)

        $aiServices = $null
        if ($ExtractionMode -eq 'standard' -and $CuEndpoint) {
            if ($CuKey) {
                $aiServices = @{ uri = $CuEndpoint; apiKey = $CuKey }
            } else {
                $aiServices = @{ uri = $CuEndpoint }
            }
        }

        $ingestion = @{ contentExtractionMode = $ExtractionMode }
        if ($aiServices) { $ingestion.aiServices = $aiServices }

        $body = @{
            name = $Name
            kind = 'azureBlob'
            description = "Foundry IQ CU demo — $ExtractionMode ingestion mode"
            azureBlobParameters = @{
                identity = @{ '@odata.type' = '#Microsoft.Azure.Search.DataSourceIdentity.None' }
                resourceUri = "https://$StorageAccount.blob.core.windows.net"
                containerName = $CuContainerName
                ingestionParameters = $ingestion
            }
        } | ConvertTo-Json -Depth 10

        Write-Host ""
        Write-Host "=== Creating knowledge source: $Name (mode: $ExtractionMode) ==="
        Invoke-SearchRest -Method PUT `
            -Url "$script:SearchEndpoint/knowledgesources/$Name`?api-version=$KnowledgeApiVersion" `
            -Body $body | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "✓ Knowledge source created"
    }

    function New-CuKnowledgeBase {
        param([string]$Name, [string]$KsName, [string]$Description)

        $body = @{
            name = $Name
            description = $Description
            knowledgeSources = @(@{ name = $KsName })
        } | ConvertTo-Json -Depth 10

        Write-Host ""
        Write-Host "=== Creating knowledge base: $Name ==="
        Invoke-SearchRest -Method PUT `
            -Url "$script:SearchEndpoint/knowledgebases/$Name`?api-version=$KnowledgeApiVersion" `
            -Body $body | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "✓ Knowledge base created"
    }

    function New-CuFoundryConnection {
        param([string]$Name, [string]$KbName)
        $mcpEndpoint = "$script:SearchEndpoint/knowledgebases/$KbName/mcp"

        $body = @{
            name = $Name
            type = 'Microsoft.MachineLearningServices/workspaces/connections'
            properties = @{
                authType = 'ProjectManagedIdentity'
                category = 'RemoteTool'
                target = $mcpEndpoint
                isSharedToAll = $true
                audience = 'https://search.azure.com/'
                metadata = @{ ApiType = 'Azure' }
            }
        } | ConvertTo-Json -Depth 10

        Write-Host ""
        Write-Host "=== Creating Foundry connection: $Name ==="
        Invoke-RestMethod -Method PUT `
            -Uri "https://management.azure.com$($script:FoundryProjectResourceId)/connections/$Name`?api-version=$FoundryConnectionApiVersion" `
            -Headers @{
                'Authorization' = "Bearer $script:ManagementToken"
                'Content-Type'  = 'application/json'
            } `
            -Body $body | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "✓ Foundry connection created"
    }

    New-CuKnowledgeSource -Name $MinimalKsName -ExtractionMode 'minimal'
    New-CuKnowledgeBase -Name $MinimalKbName -KsName $MinimalKsName `
        -Description 'Fibey IQ CU demo — minimal mode (standard text extraction, free tier)'

    New-CuKnowledgeSource -Name $StandardKsName -ExtractionMode 'standard'
    New-CuKnowledgeBase -Name $StandardKbName -KsName $StandardKsName `
        -Description 'Fibey IQ CU demo — standard mode (Azure Content Understanding, advanced table parsing)'

    New-CuFoundryConnection -Name $MinimalConnectionName -KbName $MinimalKbName
    New-CuFoundryConnection -Name $StandardConnectionName -KbName $StandardKbName

    Write-Host ""
    if ($AdminPrep) {
        Write-Host "=== [admin] Assigning Search Index Data Reader RBAC to Foundry MI ==="
        $existing = az role assignment list `
            --assignee-object-id $FoundryMiPrincipalId `
            --scope $script:SearchResourceId `
            --query "[?roleDefinitionId=='$RoleDefinitionId'].id | [0]" -o tsv
        if ($existing) {
            Write-Host "✓ Search Index Data Reader already assigned"
        } else {
            az role assignment create `
                --assignee-object-id $FoundryMiPrincipalId `
                --assignee-principal-type ServicePrincipal `
                --role $SearchIndexDataReaderRoleId `
                --scope $script:SearchResourceId `
                --only-show-errors | Out-Null
            Write-Host "✓ Search Index Data Reader assigned"
        }
    } else {
        Write-Host "ℹ Skipping role assignment (dev mode). The Foundry MI needs Search Index Data Reader on $SearchService."
        Write-Host "  If KB queries fail with 403, ask an admin to run:"
        Write-Host "    az role assignment create ``"
        Write-Host "      --assignee-object-id $FoundryMiPrincipalId ``"
        Write-Host "      --assignee-principal-type ServicePrincipal ``"
        Write-Host "      --role $SearchIndexDataReaderRoleId ``"
        Write-Host "      --scope $script:SearchResourceId"
        Write-Host "  Or rerun this script as the admin with -AdminPrep."
    }

    $MinimalMcp  = "$script:SearchEndpoint/knowledgebases/$MinimalKbName/mcp"
    $StandardMcp = "$script:SearchEndpoint/knowledgebases/$StandardKbName/mcp"

    Write-Host ""
    Write-Host "=== Done (CU Demo) ==="
    Write-Host "Minimal MCP endpoint : $MinimalMcp"
    Write-Host "Standard MCP endpoint: $StandardMcp"
    Write-Host ""
    Write-Host "Set these in your environment:"
    Write-Host "  azd env set FOUNDRY_IQ_MINIMAL_MCP_URL `"$MinimalMcp`""
    Write-Host "  azd env set FOUNDRY_IQ_STANDARD_MCP_URL `"$StandardMcp`""
    exit 0
}

# ─── Legacy default path ──────────────────────────────────────────────
Write-Host "=== Uploading documents to blob storage ==="
az storage blob upload-batch `
    --source $DocsDir --destination $ContainerName `
    --account-name $StorageAccount --auth-mode login `
    --overwrite --no-progress
$docCount = @(Get-ChildItem $DocsDir -File).Count
Write-Host "✓ Uploaded $docCount documents"

Write-Host ""
Write-Host "=== Creating search data source ==="
$dsBody = @{
    name = $DatasourceName
    type = 'azureblob'
    credentials = @{ connectionString = "ResourceId=$script:StorageResourceId;" }
    container = @{ name = $ContainerName }
} | ConvertTo-Json -Depth 10
Invoke-SearchRest -Method PUT `
    -Url "$script:SearchEndpoint/datasources/$DatasourceName`?api-version=$SearchApiVersion" `
    -Body $dsBody | ConvertTo-Json -Depth 10 | Write-Host
Write-Host "✓ Data source created"

Write-Host ""
Write-Host "=== Creating search index ==="
$idxBody = @{
    name = $IndexName
    fields = @(
        @{ name = 'id'; type = 'Edm.String'; key = $true; filterable = $true; retrievable = $true }
        @{ name = 'content'; type = 'Edm.String'; searchable = $true; retrievable = $true }
        @{ name = 'metadata_storage_path'; type = 'Edm.String'; filterable = $true; retrievable = $true }
        @{ name = 'metadata_storage_name'; type = 'Edm.String'; filterable = $true; retrievable = $true }
    )
    semantic = @{
        configurations = @(@{
            name = 'default'
            prioritizedFields = @{
                prioritizedContentFields = @(@{ fieldName = 'content' })
                titleField = @{ fieldName = 'metadata_storage_name' }
            }
        })
        defaultConfiguration = 'default'
    }
} | ConvertTo-Json -Depth 10
Invoke-SearchRest -Method PUT `
    -Url "$script:SearchEndpoint/indexes/$IndexName`?api-version=$SearchApiVersion" `
    -Body $idxBody | ConvertTo-Json -Depth 10 | Write-Host
Write-Host "✓ Index created"

Write-Host ""
Write-Host "=== Creating search indexer ==="
$indexerBody = @{
    name = $IndexerName
    dataSourceName = $DatasourceName
    targetIndexName = $IndexName
    fieldMappings = @(@{
        sourceFieldName = 'metadata_storage_path'
        targetFieldName = 'id'
        mappingFunction = @{ name = 'base64Encode' }
    })
    parameters = @{
        configuration = @{
            parsingMode = 'default'
            dataToExtract = 'contentAndMetadata'
        }
    }
    schedule = $null
} | ConvertTo-Json -Depth 10
Invoke-SearchRest -Method PUT `
    -Url "$script:SearchEndpoint/indexers/$IndexerName`?api-version=$SearchApiVersion" `
    -Body $indexerBody | ConvertTo-Json -Depth 10 | Write-Host
Write-Host "✓ Indexer created"

Write-Host ""
Write-Host "=== Running indexer ==="
Invoke-SearchRest -Method POST `
    -Url "$script:SearchEndpoint/indexers/$IndexerName/run?api-version=$SearchApiVersion" | Out-Null
Write-Host "✓ Indexer triggered — documents will be indexed shortly"

Write-Host ""
Write-Host "=== Checking indexer status ==="
Start-Sleep -Seconds 5
$status = Invoke-SearchRest -Method GET `
    -Url "$script:SearchEndpoint/indexers/$IndexerName/status?api-version=$SearchApiVersion"
$last = $status.lastResult
Write-Host "Status: $($last.status)"
Write-Host "Items processed: $($last.itemsProcessed)"
Write-Host "Items failed: $($last.itemsFailed)"

Write-Host ""
Write-Host "=== Creating knowledge source ==="
$ksBody = @{
    name = $KsName
    kind = 'searchIndex'
    description = 'Knowledge source for Fibey Field Ops FoundryIQ documents.'
    encryptionKey = $null
    searchIndexParameters = @{
        searchIndexName = $IndexName
        semanticConfigurationName = 'default'
        sourceDataFields = @(@{ name = 'metadata_storage_name' }, @{ name = 'metadata_storage_path' })
        searchFields = @(@{ name = 'content' })
    }
} | ConvertTo-Json -Depth 10
Invoke-SearchRest -Method PUT `
    -Url "$script:SearchEndpoint/knowledgesources/$KsName`?api-version=$KnowledgeApiVersion" `
    -Body $ksBody | ConvertTo-Json -Depth 10 | Write-Host
Write-Host "✓ Knowledge source created"

Write-Host ""
Write-Host "=== Creating knowledge base ==="
$kbBody = @{
    name = $KbName
    description = 'Knowledge base for Fibey Field Ops procedures, safety guidance, and troubleshooting docs.'
    knowledgeSources = @(@{ name = $KsName })
    encryptionKey = $null
} | ConvertTo-Json -Depth 10
Invoke-SearchRest -Method PUT `
    -Url "$script:SearchEndpoint/knowledgebases/$KbName`?api-version=$KnowledgeApiVersion" `
    -Body $kbBody | ConvertTo-Json -Depth 10 | Write-Host
Write-Host "✓ Knowledge base created"

Write-Host ""
Write-Host "=== Creating Foundry connection ==="
$McpEndpoint = "$script:SearchEndpoint/knowledgebases/$KbName/mcp"
$connBody = @{
    name = $ConnectionName
    type = 'Microsoft.MachineLearningServices/workspaces/connections'
    properties = @{
        authType = 'ProjectManagedIdentity'
        category = 'RemoteTool'
        target = $McpEndpoint
        isSharedToAll = $true
        audience = 'https://search.azure.com/'
        metadata = @{ ApiType = 'Azure' }
    }
} | ConvertTo-Json -Depth 10
Invoke-RestMethod -Method PUT `
    -Uri "https://management.azure.com$($script:FoundryProjectResourceId)/connections/$ConnectionName`?api-version=$FoundryConnectionApiVersion" `
    -Headers @{
        'Authorization' = "Bearer $script:ManagementToken"
        'Content-Type'  = 'application/json'
    } `
    -Body $connBody | ConvertTo-Json -Depth 10 | Write-Host
Write-Host "✓ Foundry connection created"

Write-Host ""
if ($AdminPrep) {
    Write-Host "=== [admin] Assigning Search Index Data Reader RBAC to Foundry MI ==="
    $existing = az role assignment list `
        --assignee-object-id $FoundryMiPrincipalId `
        --scope $script:SearchResourceId `
        --query "[?roleDefinitionId=='$RoleDefinitionId'].id | [0]" -o tsv
    if ($existing) {
        Write-Host "✓ Search Index Data Reader already assigned"
    } else {
        az role assignment create `
            --assignee-object-id $FoundryMiPrincipalId `
            --assignee-principal-type ServicePrincipal `
            --role $SearchIndexDataReaderRoleId `
            --scope $script:SearchResourceId `
            --only-show-errors | Out-Null
        Write-Host "✓ Search Index Data Reader assigned"
    }
} else {
    Write-Host "ℹ Skipping role assignment (dev mode). The Foundry MI needs Search Index Data Reader on $SearchService."
    Write-Host "  If KB queries fail with 403, ask an admin to run:"
    Write-Host "    az role assignment create ``"
    Write-Host "      --assignee-object-id $FoundryMiPrincipalId ``"
    Write-Host "      --assignee-principal-type ServicePrincipal ``"
    Write-Host "      --role $SearchIndexDataReaderRoleId ``"
    Write-Host "      --scope $script:SearchResourceId"
    Write-Host "  Or rerun this script as the admin with -AdminPrep."
}

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Search endpoint   : $script:SearchEndpoint"
Write-Host "Index name        : $IndexName"
Write-Host "Knowledge source  : $KsName"
Write-Host "Knowledge base    : $KbName"
Write-Host "Foundry connection: $ConnectionName"
Write-Host "MCP endpoint      : $McpEndpoint"
Write-Host ""
Write-Host "Set these in your azd environment:"
Write-Host "  azd env set AZURE_SEARCH_ENDPOINT `"$script:SearchEndpoint`""
Write-Host "  azd env set KB_NAME `"$KbName`""
