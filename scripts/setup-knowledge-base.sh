#!/usr/bin/env bash
# Upload FoundryIQ docs to blob storage and configure the full AI Search + FoundryIQ pipeline.
# Usage:
#   ./scripts/setup-knowledge-base.sh [foundry-project-endpoint]
#   ./scripts/setup-knowledge-base.sh --cu-demo [foundry-project-endpoint]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$REPO_ROOT/services/foundry-iq-docs/docs"
CU_DOCS_DIR="$REPO_ROOT/services/foundry-iq-docs/content-understanding/docs"
ENV_FILE="$REPO_ROOT/.env"

upsert_env_var() {
  local key="$1"
  local value="$2"
  local file_path="$3"
  local escaped_value

  escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//&/\\&}"

  if grep -qE "^${key}=" "$file_path"; then
    sed -i.bak "s|^${key}=.*|${key}=${escaped_value}|" "$file_path"
    rm -f "$file_path.bak"
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$file_path"
  fi
}

ensure_env_file() {
  if [ ! -f "$ENV_FILE" ] && [ -f "$REPO_ROOT/.env.example" ]; then
    cp "$REPO_ROOT/.env.example" "$ENV_FILE"
    echo "Created .env from .env.example"
  fi
}

resolve_cu_key_from_endpoint() {
  local endpoint="$1"
  local normalized_endpoint
  local account_json
  local account_name
  local account_rg
  local resolved_key

  normalized_endpoint="${endpoint%/}/"
  account_json=$(az cognitiveservices account list \
    --query "[?properties.endpoint=='${normalized_endpoint}'] | [0] | {name:name,resourceGroup:resourceGroup}" \
    -o json 2>/dev/null || true)

  if [ -z "$account_json" ] || [ "$account_json" = "null" ]; then
    return 1
  fi

  account_name=$(printf "%s" "$account_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name", ""))' 2>/dev/null || true)
  account_rg=$(printf "%s" "$account_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("resourceGroup", ""))' 2>/dev/null || true)

  if [ -z "$account_name" ] || [ -z "$account_rg" ]; then
    return 1
  fi

  resolved_key=$(az cognitiveservices account keys list \
    --name "$account_name" \
    --resource-group "$account_rg" \
    --query key1 -o tsv 2>/dev/null || true)

  if [ -z "$resolved_key" ]; then
    return 1
  fi

  printf "%s" "$resolved_key"
}

delete_search_resource_if_exists() {
  local resource_type="$1"
  local resource_name="$2"
  local api_version="$3"
  local delete_url="${SEARCH_ENDPOINT}/${resource_type}/${resource_name}?api-version=${api_version}"
  local status_code

  status_code=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "$delete_url" \
    -H "Authorization: Bearer ${SEARCH_TOKEN}")

  case "$status_code" in
    200|202|204)
      echo "  - Deleted ${resource_type}/${resource_name}"
      ;;
    404)
      echo "  - ${resource_type}/${resource_name} not found (skip)"
      ;;
    *)
      echo "  - Failed deleting ${resource_type}/${resource_name} (HTTP ${status_code})"
      exit 1
      ;;
  esac
}

delete_foundry_connection_if_exists() {
  local connection_name="$1"
  local delete_url="https://management.azure.com${FOUNDRY_PROJECT_RESOURCE_ID}/connections/${connection_name}?api-version=${FOUNDRY_CONNECTION_API_VERSION}"
  local status_code

  status_code=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "$delete_url" \
    -H "Authorization: Bearer ${MANAGEMENT_TOKEN}")

  case "$status_code" in
    200|202|204)
      echo "  - Deleted Foundry connection ${connection_name}"
      ;;
    404)
      echo "  - Foundry connection ${connection_name} not found (skip)"
      ;;
    *)
      echo "  - Failed deleting Foundry connection ${connection_name} (HTTP ${status_code})"
      exit 1
      ;;
  esac
}

cleanup_cu_demo_resources() {
  local minimal_ks_name="$1"
  local standard_ks_name="$2"
  local minimal_kb_name="$3"
  local standard_kb_name="$4"
  local minimal_connection_name="$5"
  local standard_connection_name="$6"

  local minimal_ds_name="${minimal_ks_name}-datasource"
  local minimal_indexer_name="${minimal_ks_name}-indexer"
  local minimal_skillset_name="${minimal_ks_name}-skillset"
  local minimal_index_name="${minimal_ks_name}-index"

  local standard_ds_name="${standard_ks_name}-datasource"
  local standard_indexer_name="${standard_ks_name}-indexer"
  local standard_skillset_name="${standard_ks_name}-skillset"
  local standard_index_name="${standard_ks_name}-index"

  echo ""
  echo "=== Cleaning existing CU demo resources (if any) ==="

  delete_foundry_connection_if_exists "$minimal_connection_name"
  delete_foundry_connection_if_exists "$standard_connection_name"

  delete_search_resource_if_exists "knowledgebases" "$minimal_kb_name" "$KNOWLEDGE_API_VERSION"
  delete_search_resource_if_exists "knowledgebases" "$standard_kb_name" "$KNOWLEDGE_API_VERSION"

  # Knowledge sources own generated indexers/skillsets/datasources; delete them first.
  delete_search_resource_if_exists "knowledgesources" "$minimal_ks_name" "$KNOWLEDGE_API_VERSION"
  delete_search_resource_if_exists "knowledgesources" "$standard_ks_name" "$KNOWLEDGE_API_VERSION"

  delete_search_resource_if_exists "indexers" "$minimal_indexer_name" "$SEARCH_API_VERSION"
  delete_search_resource_if_exists "indexers" "$standard_indexer_name" "$SEARCH_API_VERSION"

  delete_search_resource_if_exists "skillsets" "$minimal_skillset_name" "$SEARCH_API_VERSION"
  delete_search_resource_if_exists "skillsets" "$standard_skillset_name" "$SEARCH_API_VERSION"

  delete_search_resource_if_exists "indexes" "$minimal_index_name" "$SEARCH_API_VERSION"
  delete_search_resource_if_exists "indexes" "$standard_index_name" "$SEARCH_API_VERSION"

  delete_search_resource_if_exists "datasources" "$minimal_ds_name" "$SEARCH_API_VERSION"
  delete_search_resource_if_exists "datasources" "$standard_ds_name" "$SEARCH_API_VERSION"
}

USE_CU_DEMO=false
ADMIN_PREP=false
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage:"
  echo "  ./scripts/setup-knowledge-base.sh [foundry-project-endpoint]"
  echo "  ./scripts/setup-knowledge-base.sh --cu-demo [foundry-project-endpoint]"
  echo "  ./scripts/setup-knowledge-base.sh --admin-prep [foundry-project-endpoint]"
  echo ""
  echo "Modes:"
  echo "  default      Dev path: create datasource/index/indexer/KS/KB/Foundry-connection using data-plane RBAC (no listKeys, no admin-key)."
  echo "  --cu-demo    Dev path for the CU demo: create minimal + standard KS/KB pair for Foundry IQ ingestion comparison."
  echo "  --admin-prep Admin path: assign Search Index Data Reader to the Foundry MI on the Search service. Run once by a user with User Access Administrator."
  echo ""
  echo "Required env var (or positional arg):"
  echo "  FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>"
  echo ""
  echo "Required dev-track roles (the user running this script must have):"
  echo "  - Storage Blob Data Contributor      on the storage account"
  echo "  - Search Index Data Contributor      on the Search service"
  echo "  - Azure AI User                       on the Foundry project"
  echo "  - Reader                              on the resource group (recommended; data-plane roles imply per-resource read)"
  echo ""
  echo "Required admin-track roles (--admin-prep mode):"
  echo "  - User Access Administrator           on the Search service"
  exit 0
fi

if [[ "${1:-}" == "--cu-demo" ]]; then
  USE_CU_DEMO=true
  shift
fi

if [[ "${1:-}" == "--admin-prep" ]]; then
  ADMIN_PREP=true
  shift
fi

CONTAINER_NAME="foundry-iq-docs"
INDEX_NAME="foundry-iq-docs-index"
DATASOURCE_NAME="foundry-iq-docs-ds"
INDEXER_NAME="foundry-iq-docs-indexer"
KB_NAME="fibey-field-ops-kb"
KS_NAME="fibey-field-ops-ks"
CONNECTION_NAME="kb-fibey-field-ops-kb"

SEARCH_API_VERSION="2024-07-01"
KNOWLEDGE_API_VERSION="2026-04-01"
FOUNDRY_CONNECTION_API_VERSION="2025-10-01-preview"
SEARCH_INDEX_DATA_READER_ROLE_ID="1407120a-92aa-4202-b7e9-c0e197c71c8f"

FOUNDRY_PROJECT_ENDPOINT="${1:-${FOUNDRY_PROJECT_ENDPOINT:-}}"

if [ -z "${AZURE_RESOURCE_GROUP:-}" ]; then
  echo "AZURE_RESOURCE_GROUP must be set before running this script."
  exit 1
fi

if [ -z "$FOUNDRY_PROJECT_ENDPOINT" ]; then
  echo "FOUNDRY_PROJECT_ENDPOINT must be set (or passed as the first argument)."
  exit 1
fi

FOUNDRY_PROJECT_ENDPOINT="${FOUNDRY_PROJECT_ENDPOINT%/}"
FOUNDRY_ACCOUNT_NAME=$(printf "%s" "$FOUNDRY_PROJECT_ENDPOINT" | sed -nE 's#^https?://([^.]+)\.services\.ai\.azure\.com(/.*)?$#\1#p')
FOUNDRY_PROJECT_NAME=$(printf "%s" "$FOUNDRY_PROJECT_ENDPOINT" | sed -nE 's#^https?://[^/]+/api/projects/([^/?#]+).*$#\1#p')

if [ -z "$FOUNDRY_ACCOUNT_NAME" ] || [ -z "$FOUNDRY_PROJECT_NAME" ]; then
  echo "Could not parse account/project from FOUNDRY_PROJECT_ENDPOINT: $FOUNDRY_PROJECT_ENDPOINT"
  echo "Expected format: https://<account>.services.ai.azure.com/api/projects/<project>"
  exit 1
fi

# Resolve resource names from azd outputs
echo "Reading azd outputs..."
STORAGE_ACCOUNT=$(azd env get-value storageAccountName 2>/dev/null || \
  az storage account list -g "${AZURE_RESOURCE_GROUP}" --query "[0].name" -o tsv)
SEARCH_SERVICE=$(azd env get-value searchServiceName 2>/dev/null || \
  az search service list -g "${AZURE_RESOURCE_GROUP}" --query "[0].name" -o tsv)
SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"
MCP_ENDPOINT="${SEARCH_ENDPOINT}/knowledgebases/${KB_NAME}/mcp"

if [ -z "$STORAGE_ACCOUNT" ] || [ -z "$SEARCH_SERVICE" ]; then
  echo "Could not resolve storage account or search service from azd outputs or Azure CLI."
  exit 1
fi

SEARCH_RESOURCE_ID=$(az search service show \
  --name "$SEARCH_SERVICE" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query id -o tsv)

STORAGE_RESOURCE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --query id -o tsv)

# Search REST calls use AAD Bearer tokens (no admin-key needed).
# Requires the caller to have Search Index Data Contributor on the Search service
# and the Search service to allow AAD auth (auth-options aad or aadOrApiKey).
SEARCH_TOKEN=$(az account get-access-token \
  --resource https://search.azure.com \
  --query accessToken -o tsv)

if [ -z "$SEARCH_TOKEN" ]; then
  echo "Failed to acquire Search data-plane AAD token."
  echo "Make sure your Search service has AAD auth enabled:"
  echo "  az search service update -n $SEARCH_SERVICE -g $AZURE_RESOURCE_GROUP --auth-options aad"
  exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

FOUNDRY_PROJECT_RESOURCE_ID=$(az resource list \
  --query "[?(type=='Microsoft.CognitiveServices/accounts/projects' || type=='Microsoft.MachineLearningServices/workspaces/projects') && (contains(id, '/accounts/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}') || contains(id, '/workspaces/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}'))].id | [0]" \
  -o tsv)

if [ -z "$FOUNDRY_PROJECT_RESOURCE_ID" ]; then
  echo "Could not resolve a Foundry project resource ID from FOUNDRY_PROJECT_ENDPOINT."
  echo "Endpoint: $FOUNDRY_PROJECT_ENDPOINT"
  exit 1
fi

FOUNDRY_RESOURCE_GROUP=$(printf "%s" "$FOUNDRY_PROJECT_RESOURCE_ID" | sed -nE 's#^/subscriptions/[^/]+/resourceGroups/([^/]+)/.*$#\1#p')

if [ -z "$FOUNDRY_RESOURCE_GROUP" ]; then
  echo "Could not resolve Foundry resource group from project resource ID: $FOUNDRY_PROJECT_RESOURCE_ID"
  exit 1
fi

if [[ "$FOUNDRY_PROJECT_RESOURCE_ID" == *"/providers/Microsoft.CognitiveServices/accounts/"* ]]; then
  FOUNDRY_ACCOUNT_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT_NAME}"
else
  FOUNDRY_ACCOUNT_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${FOUNDRY_ACCOUNT_NAME}"
fi

FOUNDRY_MI_PRINCIPAL_ID=$(az resource show \
  --ids "$FOUNDRY_PROJECT_RESOURCE_ID" \
  --api-version "$FOUNDRY_CONNECTION_API_VERSION" \
  --query identity.principalId -o tsv)

if [ -z "$FOUNDRY_MI_PRINCIPAL_ID" ]; then
  FOUNDRY_MI_PRINCIPAL_ID=$(az resource show \
    --ids "$FOUNDRY_ACCOUNT_RESOURCE_ID" \
    --api-version "$FOUNDRY_CONNECTION_API_VERSION" \
    --query identity.principalId -o tsv)
fi

if [ -z "$FOUNDRY_MI_PRINCIPAL_ID" ]; then
  echo "Could not resolve the Foundry managed identity principal ID for RBAC assignment."
  exit 1
fi

ROLE_DEFINITION_ID="/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleDefinitions/${SEARCH_INDEX_DATA_READER_ROLE_ID}"
MANAGEMENT_TOKEN=$(az account get-access-token \
  --scope https://management.azure.com/.default \
  --query accessToken -o tsv)

CU_ENDPOINT="${AZURE_CONTENTUNDERSTANDING_ENDPOINT:-}"
CU_KEY="${AZURE_CONTENTUNDERSTANDING_KEY:-}"

if [[ "$USE_CU_DEMO" == "true" ]] && [ -n "$CU_ENDPOINT" ] && [ -z "$CU_KEY" ]; then
  echo "Attempting to resolve AZURE_CONTENTUNDERSTANDING_KEY from Azure (az login context)..."
  if RESOLVED_CU_KEY=$(resolve_cu_key_from_endpoint "$CU_ENDPOINT"); then
    CU_KEY="$RESOLVED_CU_KEY"
    echo "✓ Resolved CU key from AI Services account"
    ensure_env_file
    if [ -f "$ENV_FILE" ]; then
      upsert_env_var "AZURE_CONTENTUNDERSTANDING_ENDPOINT" "$CU_ENDPOINT" "$ENV_FILE"
      upsert_env_var "AZURE_CONTENTUNDERSTANDING_KEY" "$CU_KEY" "$ENV_FILE"
      echo "✓ Updated AZURE_CONTENTUNDERSTANDING_ENDPOINT and AZURE_CONTENTUNDERSTANDING_KEY in .env"
    fi
  else
    echo "⚠ Could not auto-resolve AZURE_CONTENTUNDERSTANDING_KEY from endpoint: $CU_ENDPOINT"
    echo "  Provide AZURE_CONTENTUNDERSTANDING_KEY manually if standard mode needs key-based auth."
  fi
fi

echo ""
echo "Storage Account       : $STORAGE_ACCOUNT"
echo "Search Service        : $SEARCH_SERVICE"
echo "Search Endpoint       : $SEARCH_ENDPOINT"
echo "Foundry Endpoint      : $FOUNDRY_PROJECT_ENDPOINT"
echo "Foundry Resource Group: $FOUNDRY_RESOURCE_GROUP"
echo "Foundry Account       : $FOUNDRY_ACCOUNT_NAME"
echo "Foundry Project       : $FOUNDRY_PROJECT_NAME"
if [[ "$USE_CU_DEMO" == "true" ]]; then
  echo "CU Endpoint           : ${CU_ENDPOINT:-<not set — standard mode uses default AI services>}"
fi
echo ""

if [[ "$USE_CU_DEMO" == "true" ]]; then
  CU_CONTAINER_NAME="foundry-iq-cu-demo"
  MINIMAL_KS_NAME="fibey-iq-minimal-ks"
  MINIMAL_KB_NAME="fibey-iq-minimal-kb"
  MINIMAL_CONNECTION_NAME="kb-fibey-iq-minimal"
  STANDARD_KS_NAME="fibey-iq-standard-ks"
  STANDARD_KB_NAME="fibey-iq-standard-kb"
  STANDARD_CONNECTION_NAME="kb-fibey-iq-standard"

  if { [ ! -d "$DOCS_DIR" ] || [ -z "$(ls -A "$DOCS_DIR" 2>/dev/null)" ]; }; then
    echo "ERROR: No base FoundryIQ docs found in $DOCS_DIR"
    exit 1
  fi

  if { [ ! -d "$CU_DOCS_DIR" ] || [ -z "$(ls -A "$CU_DOCS_DIR" 2>/dev/null)" ]; }; then
    echo "ERROR: No CU demo docs found in $CU_DOCS_DIR"
    exit 1
  fi

  cleanup_cu_demo_resources \
    "$MINIMAL_KS_NAME" \
    "$STANDARD_KS_NAME" \
    "$MINIMAL_KB_NAME" \
    "$STANDARD_KB_NAME" \
    "$MINIMAL_CONNECTION_NAME" \
    "$STANDARD_CONNECTION_NAME"

  echo "=== Creating blob container: $CU_CONTAINER_NAME ==="
  az storage container create \
    --name "$CU_CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --only-show-errors 2>&1 | grep -v "^$" || true
  sleep 5

  echo ""
  echo "=== Uploading CU + base knowledge documents ==="
  az storage blob upload-batch \
    --source "$DOCS_DIR" \
    --destination "$CU_CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --overwrite \
    --no-progress

  az storage blob upload-batch \
    --source "$CU_DOCS_DIR" \
    --destination "$CU_CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --overwrite \
    --no-progress

  BASE_DOC_COUNT=$(find "$DOCS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
  CU_DOC_COUNT=$(find "$CU_DOCS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
  TOTAL_DOC_COUNT=$((BASE_DOC_COUNT + CU_DOC_COUNT))
  echo "✓ Uploaded $TOTAL_DOC_COUNT document(s)"

  create_cu_knowledge_source() {
    local ks_name="$1"
    local extraction_mode="$2"

    if [ "$extraction_mode" = "standard" ] && [ -n "$CU_ENDPOINT" ]; then
      if [ -n "$CU_KEY" ]; then
        AI_SERVICES_BLOCK=", \"aiServices\": { \"uri\": \"${CU_ENDPOINT}\", \"apiKey\": \"${CU_KEY}\" }"
      else
        AI_SERVICES_BLOCK=", \"aiServices\": { \"uri\": \"${CU_ENDPOINT}\" }"
      fi
    else
      AI_SERVICES_BLOCK=""
    fi

    echo ""
    echo "=== Creating knowledge source: $ks_name (mode: $extraction_mode) ==="
    # Use managed-identity blob auth instead of connectionString — Search MI
    # reads blobs with Storage Blob Data Reader (assigned by --admin-prep).
    curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/knowledgesources/${ks_name}?api-version=${KNOWLEDGE_API_VERSION}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SEARCH_TOKEN}" \
      -d "{
        \"name\": \"${ks_name}\",
        \"kind\": \"azureBlob\",
        \"description\": \"Foundry IQ CU demo — ${extraction_mode} ingestion mode\",
        \"azureBlobParameters\": {
          \"identity\": { \"@odata.type\": \"#Microsoft.Azure.Search.DataSourceIdentity.None\" },
          \"resourceUri\": \"https://${STORAGE_ACCOUNT}.blob.core.windows.net\",
          \"containerName\": \"${CU_CONTAINER_NAME}\",
          \"ingestionParameters\": {
            \"contentExtractionMode\": \"${extraction_mode}\"
            ${AI_SERVICES_BLOCK}
          }
        }
      }" | python3 -m json.tool
    echo "✓ Knowledge source created"
  }

  create_cu_knowledge_base() {
    local kb_name="$1"
    local ks_name="$2"
    local description="$3"

    echo ""
    echo "=== Creating knowledge base: $kb_name ==="
    curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/knowledgebases/${kb_name}?api-version=${KNOWLEDGE_API_VERSION}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SEARCH_TOKEN}" \
      -d "{
        \"name\": \"${kb_name}\",
        \"description\": \"${description}\",
        \"knowledgeSources\": [{ \"name\": \"${ks_name}\" }]
      }" | python3 -m json.tool
    echo "✓ Knowledge base created"
  }

  create_cu_foundry_connection() {
    local connection_name="$1"
    local kb_name="$2"
    local mcp_endpoint="${SEARCH_ENDPOINT}/knowledgebases/${kb_name}/mcp"

    echo ""
    echo "=== Creating Foundry connection: $connection_name ==="
    curl --fail-with-body -sS -X PUT "https://management.azure.com${FOUNDRY_PROJECT_RESOURCE_ID}/connections/${connection_name}?api-version=${FOUNDRY_CONNECTION_API_VERSION}" \
      -H "Authorization: Bearer ${MANAGEMENT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${connection_name}\",
        \"type\": \"Microsoft.MachineLearningServices/workspaces/connections\",
        \"properties\": {
          \"authType\": \"ProjectManagedIdentity\",
          \"category\": \"RemoteTool\",
          \"target\": \"${mcp_endpoint}\",
          \"isSharedToAll\": true,
          \"audience\": \"https://search.azure.com/\",
          \"metadata\": { \"ApiType\": \"Azure\" }
        }
      }" | python3 -m json.tool
    echo "✓ Foundry connection created"
  }

  create_cu_knowledge_source "$MINIMAL_KS_NAME" "minimal"
  create_cu_knowledge_base "$MINIMAL_KB_NAME" "$MINIMAL_KS_NAME" \
    "Fibey IQ CU demo — minimal mode (standard text extraction, free tier)"

  create_cu_knowledge_source "$STANDARD_KS_NAME" "standard"
  create_cu_knowledge_base "$STANDARD_KB_NAME" "$STANDARD_KS_NAME" \
    "Fibey IQ CU demo — standard mode (Azure Content Understanding, advanced table parsing)"

  create_cu_foundry_connection "$MINIMAL_CONNECTION_NAME" "$MINIMAL_KB_NAME"
  create_cu_foundry_connection "$STANDARD_CONNECTION_NAME" "$STANDARD_KB_NAME"

  echo ""
  if [[ "$ADMIN_PREP" == "true" ]]; then
    echo "=== [admin] Assigning Search Index Data Reader RBAC to Foundry MI ==="
    EXISTING_ASSIGNMENT=$(az role assignment list \
      --assignee-object-id "$FOUNDRY_MI_PRINCIPAL_ID" \
      --scope "$SEARCH_RESOURCE_ID" \
      --query "[?roleDefinitionId=='${ROLE_DEFINITION_ID}'].id | [0]" \
      -o tsv)

    if [ -n "$EXISTING_ASSIGNMENT" ]; then
      echo "✓ Search Index Data Reader already assigned"
    else
      az role assignment create \
        --assignee-object-id "$FOUNDRY_MI_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "$SEARCH_INDEX_DATA_READER_ROLE_ID" \
        --scope "$SEARCH_RESOURCE_ID" \
        --only-show-errors >/dev/null
      echo "✓ Search Index Data Reader assigned"
    fi
  else
    echo "ℹ Skipping role assignment (dev mode). The Foundry MI needs Search Index Data Reader on $SEARCH_SERVICE."
    echo "  If KB queries fail with 403, ask an admin to run:"
    echo "    az role assignment create \\"
    echo "      --assignee-object-id $FOUNDRY_MI_PRINCIPAL_ID \\"
    echo "      --assignee-principal-type ServicePrincipal \\"
    echo "      --role $SEARCH_INDEX_DATA_READER_ROLE_ID \\"
    echo "      --scope $SEARCH_RESOURCE_ID"
    echo "  Or rerun this script as the admin with --admin-prep."
  fi

  MINIMAL_MCP="${SEARCH_ENDPOINT}/knowledgebases/${MINIMAL_KB_NAME}/mcp"
  STANDARD_MCP="${SEARCH_ENDPOINT}/knowledgebases/${STANDARD_KB_NAME}/mcp"

  echo ""
  echo "=== Done (CU Demo) ==="
  echo "Minimal MCP endpoint : ${MINIMAL_MCP}"
  echo "Standard MCP endpoint: ${STANDARD_MCP}"
  echo ""
  echo "Set these in your environment:"
  echo "  azd env set FOUNDRY_IQ_MINIMAL_MCP_URL \"${MINIMAL_MCP}\""
  echo "  azd env set FOUNDRY_IQ_STANDARD_MCP_URL \"${STANDARD_MCP}\""
  exit 0
fi

# ─── 1. Upload documents ───────────────────────────────────────────────
echo "=== Uploading documents to blob storage ==="
az storage blob upload-batch \
  --source "$DOCS_DIR" \
  --destination "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --overwrite \
  --no-progress
echo "✓ Uploaded $(find "$DOCS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ') documents"

# ─── 2. Create data source ─────────────────────────────────────────────
echo ""
echo "=== Creating search data source ==="
curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/datasources/${DATASOURCE_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}" \
  -d "{
    \"name\": \"${DATASOURCE_NAME}\",
    \"type\": \"azureblob\",
    \"credentials\": {
      \"connectionString\": \"ResourceId=${STORAGE_RESOURCE_ID};\"
    },
    \"container\": {
      \"name\": \"${CONTAINER_NAME}\"
    }
  }" | python3 -m json.tool
echo "✓ Data source created"

# ─── 3. Create search index ────────────────────────────────────────────
echo ""
echo "=== Creating search index ==="
curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/indexes/${INDEX_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}" \
  -d "{
    \"name\": \"${INDEX_NAME}\",
    \"fields\": [
      {\"name\": \"id\", \"type\": \"Edm.String\", \"key\": true, \"filterable\": true, \"retrievable\": true},
      {\"name\": \"content\", \"type\": \"Edm.String\", \"searchable\": true, \"retrievable\": true},
      {\"name\": \"metadata_storage_path\", \"type\": \"Edm.String\", \"filterable\": true, \"retrievable\": true},
      {\"name\": \"metadata_storage_name\", \"type\": \"Edm.String\", \"filterable\": true, \"retrievable\": true}
    ],
    \"semantic\": {
      \"configurations\": [
        {
          \"name\": \"default\",
          \"prioritizedFields\": {
            \"prioritizedContentFields\": [{\"fieldName\": \"content\"}],
            \"titleField\": {\"fieldName\": \"metadata_storage_name\"}
          }
        }
      ],
      \"defaultConfiguration\": \"default\"
    }
  }" | python3 -m json.tool
echo "✓ Index created"

# ─── 4. Create indexer ─────────────────────────────────────────────────
echo ""
echo "=== Creating search indexer ==="
curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}" \
  -d "{
    \"name\": \"${INDEXER_NAME}\",
    \"dataSourceName\": \"${DATASOURCE_NAME}\",
    \"targetIndexName\": \"${INDEX_NAME}\",
    \"fieldMappings\": [
      {
        \"sourceFieldName\": \"metadata_storage_path\",
        \"targetFieldName\": \"id\",
        \"mappingFunction\": {
          \"name\": \"base64Encode\"
        }
      }
    ],
    \"parameters\": {
      \"configuration\": {
        \"parsingMode\": \"default\",
        \"dataToExtract\": \"contentAndMetadata\"
      }
    },
    \"schedule\": null
  }" | python3 -m json.tool
echo "✓ Indexer created"

# ─── 5. Run indexer ────────────────────────────────────────────────────
echo ""
echo "=== Running indexer ==="
curl --fail-with-body -sS -X POST "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}/run?api-version=${SEARCH_API_VERSION}" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}" \
  -H "Content-Length: 0" \
  -w "HTTP %{http_code}"
echo ""
echo "✓ Indexer triggered — documents will be indexed shortly"

# ─── 6. Check status ───────────────────────────────────────────────────
echo ""
echo "=== Checking indexer status ==="
sleep 5
STATUS=$(curl --fail-with-body -sS "${SEARCH_ENDPOINT}/indexers/${INDEXER_NAME}/status?api-version=${SEARCH_API_VERSION}" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}")
echo "$STATUS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
hist = d.get('lastResult', {})
print(f\"Status: {hist.get('status', 'unknown')}\")
print(f\"Items processed: {hist.get('itemsProcessed', 0)}\")
print(f\"Items failed: {hist.get('itemsFailed', 0)}\")
"

# ─── 7. Create knowledge source ────────────────────────────────────────
echo ""
echo "=== Creating knowledge source ==="
curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/knowledgesources/${KS_NAME}?api-version=${KNOWLEDGE_API_VERSION}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}" \
  -d "{
    \"name\": \"${KS_NAME}\",
    \"kind\": \"searchIndex\",
    \"description\": \"Knowledge source for Fibey Field Ops FoundryIQ documents.\",
    \"encryptionKey\": null,
    \"searchIndexParameters\": {
      \"searchIndexName\": \"${INDEX_NAME}\",
      \"semanticConfigurationName\": \"default\",
      \"sourceDataFields\": [
        { \"name\": \"metadata_storage_name\" },
        { \"name\": \"metadata_storage_path\" }
      ],
      \"searchFields\": [
        { \"name\": \"content\" }
      ]
    }
  }" | python3 -m json.tool
echo "✓ Knowledge source created"

# ─── 8. Create knowledge base ──────────────────────────────────────────
echo ""
echo "=== Creating knowledge base ==="
curl --fail-with-body -sS -X PUT "${SEARCH_ENDPOINT}/knowledgebases/${KB_NAME}?api-version=${KNOWLEDGE_API_VERSION}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SEARCH_TOKEN}" \
  -d "{
    \"name\": \"${KB_NAME}\",
    \"description\": \"Knowledge base for Fibey Field Ops procedures, safety guidance, and troubleshooting docs.\",
    \"knowledgeSources\": [
      { \"name\": \"${KS_NAME}\" }
    ],
    \"encryptionKey\": null
  }" | python3 -m json.tool
echo "✓ Knowledge base created"

# ─── 9. Create Foundry connection ──────────────────────────────────────
echo ""
echo "=== Creating Foundry connection ==="
curl --fail-with-body -sS -X PUT "https://management.azure.com${FOUNDRY_PROJECT_RESOURCE_ID}/connections/${CONNECTION_NAME}?api-version=${FOUNDRY_CONNECTION_API_VERSION}" \
  -H "Authorization: Bearer ${MANAGEMENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${CONNECTION_NAME}\",
    \"type\": \"Microsoft.MachineLearningServices/workspaces/connections\",
    \"properties\": {
      \"authType\": \"ProjectManagedIdentity\",
      \"category\": \"RemoteTool\",
      \"target\": \"${MCP_ENDPOINT}\",
      \"isSharedToAll\": true,
      \"audience\": \"https://search.azure.com/\",
      \"metadata\": {
        \"ApiType\": \"Azure\"
      }
    }
  }" | python3 -m json.tool
echo "✓ Foundry connection created"

# ─── 10. Assign RBAC (admin only) ──────────────────────────────────────
echo ""
if [[ "$ADMIN_PREP" == "true" ]]; then
  echo "=== [admin] Assigning Search Index Data Reader RBAC to Foundry MI ==="
  EXISTING_ASSIGNMENT=$(az role assignment list \
    --assignee-object-id "$FOUNDRY_MI_PRINCIPAL_ID" \
    --scope "$SEARCH_RESOURCE_ID" \
    --query "[?roleDefinitionId=='${ROLE_DEFINITION_ID}'].id | [0]" \
    -o tsv)

  if [ -n "$EXISTING_ASSIGNMENT" ]; then
    echo "✓ Search Index Data Reader already assigned"
  else
    az role assignment create \
      --assignee-object-id "$FOUNDRY_MI_PRINCIPAL_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "$SEARCH_INDEX_DATA_READER_ROLE_ID" \
      --scope "$SEARCH_RESOURCE_ID" \
      --only-show-errors >/dev/null
    echo "✓ Search Index Data Reader assigned"
  fi
else
  echo "ℹ Skipping role assignment (dev mode). The Foundry MI needs Search Index Data Reader on $SEARCH_SERVICE."
  echo "  If KB queries fail with 403, ask an admin to run:"
  echo "    az role assignment create \\"
  echo "      --assignee-object-id $FOUNDRY_MI_PRINCIPAL_ID \\"
  echo "      --assignee-principal-type ServicePrincipal \\"
  echo "      --role $SEARCH_INDEX_DATA_READER_ROLE_ID \\"
  echo "      --scope $SEARCH_RESOURCE_ID"
  echo "  Or rerun this script as the admin with --admin-prep."
fi

echo ""
echo "=== Done ==="
echo "Search endpoint   : ${SEARCH_ENDPOINT}"
echo "Index name        : ${INDEX_NAME}"
echo "Knowledge source  : ${KS_NAME}"
echo "Knowledge base    : ${KB_NAME}"
echo "Foundry connection: ${CONNECTION_NAME}"
echo "MCP endpoint      : ${MCP_ENDPOINT}"
echo ""
echo "Set these in your azd environment:"
echo "  azd env set AZURE_SEARCH_ENDPOINT \"${SEARCH_ENDPOINT}\""
echo "  azd env set KB_NAME \"${KB_NAME}\""
