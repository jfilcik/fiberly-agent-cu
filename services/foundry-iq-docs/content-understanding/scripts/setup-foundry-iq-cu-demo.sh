#!/usr/bin/env bash
# Set up the Foundry IQ CU Demo — creates two knowledge bases (minimal and standard)
# that index the same PDF documents but with different contentExtractionMode settings.
# This enables the side-by-side ingestion quality demo in the Fibey UI.
#
# Usage:
#   ./setup-foundry-iq-cu-demo.sh [foundry-project-endpoint]
#   ./setup-foundry-iq-cu-demo.sh --teardown   [args...]   # delete all resources created by this script
#   ./setup-foundry-iq-cu-demo.sh --recreate   [args...]   # teardown then re-create
#
# Required env vars (or pass as positional args):
#   AZURE_RESOURCE_GROUP    — resource group that contains the search service + storage
#   FOUNDRY_PROJECT_ENDPOINT — https://<account>.services.ai.azure.com/api/projects/<project>
#
# Optional env vars:
#   AZURE_SEARCH_ADMIN_KEY  — search admin key; fetched via az CLI if not set
#   AZURE_CONTENTUNDERSTANDING_ENDPOINT — AI services endpoint for standard mode
#   AZURE_CONTENTUNDERSTANDING_KEY      — AI services key for standard mode
#
# After the script completes it prints two MCP endpoint URLs:
#   FOUNDRY_IQ_MINIMAL_MCP_URL  — set in your .env for minimal mode
#   FOUNDRY_IQ_STANDARD_MCP_URL — set in your .env for standard mode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Script lives at services/foundry-iq-docs/content-understanding/scripts/
# Repo root is 4 levels up
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
CU_DOCS_DIR="$SCRIPT_DIR/../docs"
BASE_DOCS_DIR="$REPO_ROOT/services/foundry-iq-docs/docs"

# ── Mode flags ─────────────────────────────────────────────────────────────────
MODE="setup"
if [[ "${1:-}" == "--teardown" ]]; then
  MODE="teardown"; shift
elif [[ "${1:-}" == "--recreate" ]]; then
  MODE="recreate"; shift
fi

# ── Resource names ─────────────────────────────────────────────────────────────
CONTAINER_NAME="foundry-iq-cu-demo"

# Minimal mode (standard text extraction — no CU charge)
MINIMAL_KS_NAME="fibey-iq-minimal-ks"
MINIMAL_KB_NAME="fibey-iq-minimal-kb"
MINIMAL_CONNECTION_NAME="kb-fibey-iq-minimal"

# Standard mode (Azure Content Understanding — enables advanced table parsing)
STANDARD_KS_NAME="fibey-iq-standard-ks"
STANDARD_KB_NAME="fibey-iq-standard-kb"
STANDARD_CONNECTION_NAME="kb-fibey-iq-standard"

KNOWLEDGE_API_VERSION="2026-04-01"
FOUNDRY_CONNECTION_API_VERSION="2025-10-01-preview"
SEARCH_INDEX_DATA_READER_ROLE_ID="1407120a-92aa-4202-b7e9-c0e197c71c8f"

# ── Arguments / env vars ────────────────────────────────────────────────────────
FOUNDRY_PROJECT_ENDPOINT="${1:-${FOUNDRY_PROJECT_ENDPOINT:-}}"

if [ -z "${AZURE_RESOURCE_GROUP:-}" ]; then
  echo "ERROR: AZURE_RESOURCE_GROUP must be set."
  exit 1
fi

if [ -z "$FOUNDRY_PROJECT_ENDPOINT" ]; then
  echo "ERROR: FOUNDRY_PROJECT_ENDPOINT must be set (or passed as the first argument)."
  echo "Expected format: https://<account>.services.ai.azure.com/api/projects/<project>"
  exit 1
fi

FOUNDRY_PROJECT_ENDPOINT="${FOUNDRY_PROJECT_ENDPOINT%/}"
FOUNDRY_ACCOUNT_NAME=$(printf "%s" "$FOUNDRY_PROJECT_ENDPOINT" | sed -nE 's#^https?://([^.]+)\.services\.ai\.azure\.com(/.*)?$#\1#p')
FOUNDRY_PROJECT_NAME=$(printf "%s" "$FOUNDRY_PROJECT_ENDPOINT" | sed -nE 's#^https?://[^/]+/api/projects/([^/?#]+).*$#\1#p')

if [ -z "$FOUNDRY_ACCOUNT_NAME" ] || [ -z "$FOUNDRY_PROJECT_NAME" ]; then
  echo "ERROR: Could not parse account/project from FOUNDRY_PROJECT_ENDPOINT: $FOUNDRY_PROJECT_ENDPOINT"
  echo "Expected format: https://<account>.services.ai.azure.com/api/projects/<project>"
  exit 1
fi

if [[ "$MODE" == "setup" ]] && { [ ! -d "$CU_DOCS_DIR" ] || [ -z "$(ls -A "$CU_DOCS_DIR" 2>/dev/null)" ]; }; then
  echo "ERROR: No CU demo documents found in $CU_DOCS_DIR"
  exit 1
fi

if [[ "$MODE" == "setup" ]] && { [ ! -d "$BASE_DOCS_DIR" ] || [ -z "$(ls -A "$BASE_DOCS_DIR" 2>/dev/null)" ]; }; then
  echo "ERROR: No base FoundryIQ docs found in $BASE_DOCS_DIR"
  exit 1
fi

# ── Resolve Azure resources ─────────────────────────────────────────────────────
echo "Reading azd / az outputs..."

STORAGE_ACCOUNT=$(azd env get-value storageAccountName 2>/dev/null || \
  az storage account list -g "${AZURE_RESOURCE_GROUP}" --query "[0].name" -o tsv)
SEARCH_SERVICE=$(azd env get-value searchServiceName 2>/dev/null || \
  az search service list -g "${AZURE_RESOURCE_GROUP}" --query "[0].name" -o tsv)

if [ -z "$STORAGE_ACCOUNT" ] || [ -z "$SEARCH_SERVICE" ]; then
  echo "ERROR: Could not resolve storage account or search service."
  exit 1
fi

SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"

STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
  --name "$STORAGE_ACCOUNT" --query connectionString -o tsv)

SEARCH_ADMIN_KEY="${AZURE_SEARCH_ADMIN_KEY:-}"
if [ -z "$SEARCH_ADMIN_KEY" ]; then
  SEARCH_ADMIN_KEY=$(az search admin-key show \
    --service-name "$SEARCH_SERVICE" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --query primaryKey -o tsv)
fi

SEARCH_RESOURCE_ID=$(az search service show \
  --name "$SEARCH_SERVICE" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query id -o tsv)

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

FOUNDRY_PROJECT_RESOURCE_ID=$(az resource list \
  --query "[?(type=='Microsoft.CognitiveServices/accounts/projects' || type=='Microsoft.MachineLearningServices/workspaces/projects') && (contains(id, '/accounts/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}') || contains(id, '/workspaces/${FOUNDRY_ACCOUNT_NAME}/projects/${FOUNDRY_PROJECT_NAME}'))].id | [0]" \
  -o tsv)

if [ -z "${FOUNDRY_PROJECT_RESOURCE_ID:-}" ]; then
  echo "ERROR: Could not resolve Foundry project resource ID from FOUNDRY_PROJECT_ENDPOINT."
  echo "Endpoint: $FOUNDRY_PROJECT_ENDPOINT"
  exit 1
fi

FOUNDRY_RESOURCE_GROUP=$(printf "%s" "$FOUNDRY_PROJECT_RESOURCE_ID" | sed -nE 's#^/subscriptions/[^/]+/resourceGroups/([^/]+)/.*$#\1#p')

if [ -z "$FOUNDRY_RESOURCE_GROUP" ]; then
  echo "ERROR: Could not resolve Foundry resource group from project resource ID: $FOUNDRY_PROJECT_RESOURCE_ID"
  exit 1
fi

if [[ "$FOUNDRY_PROJECT_RESOURCE_ID" == *"/providers/Microsoft.CognitiveServices/accounts/"* ]]; then
  FOUNDRY_RESOURCE_PROVIDER="Microsoft.CognitiveServices/accounts"
  _ACCOUNT_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${FOUNDRY_ACCOUNT_NAME}"
else
  FOUNDRY_RESOURCE_PROVIDER="Microsoft.MachineLearningServices/workspaces"
  _ACCOUNT_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FOUNDRY_RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${FOUNDRY_ACCOUNT_NAME}"
fi

echo "Foundry resource provider: $FOUNDRY_RESOURCE_PROVIDER"

# Get managed identity — CognitiveServices accounts use systemData or identity
FOUNDRY_MI_PRINCIPAL_ID=$(az resource show \
  --ids "$FOUNDRY_PROJECT_RESOURCE_ID" \
  --api-version "$FOUNDRY_CONNECTION_API_VERSION" \
  --query "identity.principalId" -o tsv 2>/dev/null || echo "")

if [ -z "$FOUNDRY_MI_PRINCIPAL_ID" ]; then
  # Try the account-level identity
  FOUNDRY_MI_PRINCIPAL_ID=$(az resource show \
    --ids "${_ACCOUNT_ID}" \
    --api-version "$FOUNDRY_CONNECTION_API_VERSION" \
    --query "identity.principalId" -o tsv 2>/dev/null || echo "")
fi

if [ -z "$FOUNDRY_MI_PRINCIPAL_ID" ]; then
  # CognitiveServices: use the account directly with its own API version
  FOUNDRY_MI_PRINCIPAL_ID=$(az cognitiveservices account show \
    --name "$FOUNDRY_ACCOUNT_NAME" \
    --resource-group "$FOUNDRY_RESOURCE_GROUP" \
    --query "identity.principalId" -o tsv 2>/dev/null || echo "")
fi

MANAGEMENT_TOKEN=$(az account get-access-token \
  --scope https://management.azure.com/.default \
  --query accessToken -o tsv)

# AI Services for standard mode (optional — can be same as Foundry AI endpoint)
CU_ENDPOINT="${AZURE_CONTENTUNDERSTANDING_ENDPOINT:-}"
CU_KEY="${AZURE_CONTENTUNDERSTANDING_KEY:-}"

echo ""
echo "Storage Account       : $STORAGE_ACCOUNT"
echo "Search Service        : $SEARCH_SERVICE"
echo "Foundry Endpoint      : $FOUNDRY_PROJECT_ENDPOINT"
echo "Foundry Resource Group: $FOUNDRY_RESOURCE_GROUP"
echo "Foundry Account       : $FOUNDRY_ACCOUNT_NAME"
echo "Foundry Project       : $FOUNDRY_PROJECT_NAME"
echo "CU Endpoint           : ${CU_ENDPOINT:-<not set — standard mode will use default AI services>}"
echo ""

# ─── Teardown helpers ──────────────────────────────────────────────────────────
delete_foundry_connection() {
  local connection_name="$1"
  echo "  Deleting Foundry connection: $connection_name"
  curl -sS -o /dev/null -w "  HTTP %{http_code}\n" -X DELETE \
    "https://management.azure.com${FOUNDRY_PROJECT_RESOURCE_ID}/connections/${connection_name}?api-version=${FOUNDRY_CONNECTION_API_VERSION}" \
    -H "Authorization: Bearer ${MANAGEMENT_TOKEN}" || true
}

delete_kb() {
  local kb_name="$1"
  echo "  Deleting knowledge base: $kb_name"
  curl -sS -o /dev/null -w "  HTTP %{http_code}\n" -X DELETE \
    "${SEARCH_ENDPOINT}/knowledgebases/${kb_name}?api-version=${KNOWLEDGE_API_VERSION}" \
    -H "api-key: ${SEARCH_ADMIN_KEY}" || true
}

delete_ks() {
  local ks_name="$1"
  echo "  Deleting knowledge source: $ks_name"
  curl -sS -o /dev/null -w "  HTTP %{http_code}\n" -X DELETE \
    "${SEARCH_ENDPOINT}/knowledgesources/${ks_name}?api-version=${KNOWLEDGE_API_VERSION}" \
    -H "api-key: ${SEARCH_ADMIN_KEY}" || true
}

teardown_all() {
  echo ""
  echo "=== Tearing down Foundry IQ CU Demo resources ==="
  delete_foundry_connection "$MINIMAL_CONNECTION_NAME"
  delete_foundry_connection "$STANDARD_CONNECTION_NAME"
  delete_kb "$MINIMAL_KB_NAME"
  delete_kb "$STANDARD_KB_NAME"
  delete_ks "$MINIMAL_KS_NAME"
  delete_ks "$STANDARD_KS_NAME"
  echo "  Deleting blob container: $CONTAINER_NAME"
  az storage container delete \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode key \
    --only-show-errors 2>&1 || true
  echo "✓ Teardown complete"
}

# ─── Mode routing ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "teardown" ]]; then
  teardown_all
  exit 0
fi

if [[ "$MODE" == "recreate" ]]; then
  teardown_all
  echo ""
  echo "=== Recreating resources ==="
fi

# ─── 1. Create blob container ──────────────────────────────────────────────────
echo "=== Creating blob container: $CONTAINER_NAME ==="
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode key \
  --only-show-errors 2>&1 | grep -v "^$" || true

# Wait for container to be fully available after creation/deletion cycle
sleep 5
echo "✓ Container ready"

# ─── 2. Upload CU + base documents ─────────────────────────────────────────────
echo ""
echo "=== Uploading CU + base knowledge documents ==="
az storage blob upload-batch \
  --source "$BASE_DOCS_DIR" \
  --destination "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode key \
  --overwrite \
  --no-progress

az storage blob upload-batch \
  --source "$CU_DOCS_DIR" \
  --destination "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode key \
  --overwrite \
  --no-progress
BASE_DOC_COUNT=$(find "$BASE_DOCS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
CU_DOC_COUNT=$(find "$CU_DOCS_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')
DOC_COUNT=$((BASE_DOC_COUNT + CU_DOC_COUNT))
echo "✓ Uploaded $DOC_COUNT document(s)"

# Helper: create knowledge source with contentExtractionMode
create_blob_ks() {
  local ks_name="$1"
  local extraction_mode="$2"

  echo ""
  echo "=== Creating knowledge source: $ks_name (mode: $extraction_mode) ==="

  # Build aiServices block only if endpoint is set and mode is standard
  if [ "$extraction_mode" = "standard" ] && [ -n "$CU_ENDPOINT" ]; then
    if [ -n "$CU_KEY" ]; then
      AI_SERVICES_BLOCK=", \"aiServices\": { \"uri\": \"${CU_ENDPOINT}\", \"apiKey\": \"${CU_KEY}\" }"
    else
      AI_SERVICES_BLOCK=", \"aiServices\": { \"uri\": \"${CU_ENDPOINT}\" }"
    fi
  else
    AI_SERVICES_BLOCK=""
  fi

  curl --fail-with-body -sS -X PUT \
    "${SEARCH_ENDPOINT}/knowledgesources/${ks_name}?api-version=${KNOWLEDGE_API_VERSION}" \
    -H "Content-Type: application/json" \
    -H "api-key: ${SEARCH_ADMIN_KEY}" \
    -d "{
      \"name\": \"${ks_name}\",
      \"kind\": \"azureBlob\",
      \"description\": \"Foundry IQ CU demo — ${extraction_mode} ingestion mode\",
      \"azureBlobParameters\": {
        \"connectionString\": \"${STORAGE_CONNECTION_STRING}\",
        \"containerName\": \"${CONTAINER_NAME}\",
        \"ingestionParameters\": {
          \"contentExtractionMode\": \"${extraction_mode}\"
          ${AI_SERVICES_BLOCK}
        }
      }
    }" | python3 -m json.tool || true
  echo "✓ Knowledge source created: $ks_name"
}

# Helper: create knowledge base
create_kb() {
  local kb_name="$1"
  local ks_name="$2"
  local description="$3"

  echo ""
  echo "=== Creating knowledge base: $kb_name ==="
  curl --fail-with-body -sS -X PUT \
    "${SEARCH_ENDPOINT}/knowledgebases/${kb_name}?api-version=${KNOWLEDGE_API_VERSION}" \
    -H "Content-Type: application/json" \
    -H "api-key: ${SEARCH_ADMIN_KEY}" \
    -d "{
      \"name\": \"${kb_name}\",
      \"description\": \"${description}\",
      \"knowledgeSources\": [{ \"name\": \"${ks_name}\" }]
    }" | python3 -m json.tool || true
  echo "✓ Knowledge base created: $kb_name"
}

# Helper: create Foundry connection
create_foundry_connection() {
  local connection_name="$1"
  local kb_name="$2"

  MCP_ENDPOINT="${SEARCH_ENDPOINT}/knowledgebases/${kb_name}/mcp"

  # Connection type differs by resource provider generation
  if [[ "$FOUNDRY_RESOURCE_PROVIDER" == "Microsoft.CognitiveServices/accounts" ]]; then
    CONN_TYPE="Microsoft.CognitiveServices/accounts/connections"
  else
    CONN_TYPE="Microsoft.MachineLearningServices/workspaces/connections"
  fi

  echo ""
  echo "=== Creating Foundry connection: $connection_name ==="
  curl --fail-with-body -sS -X PUT \
    "https://management.azure.com${FOUNDRY_PROJECT_RESOURCE_ID}/connections/${connection_name}?api-version=${FOUNDRY_CONNECTION_API_VERSION}" \
    -H "Authorization: Bearer ${MANAGEMENT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${connection_name}\",
      \"type\": \"${CONN_TYPE}\",
      \"properties\": {
        \"authType\": \"ProjectManagedIdentity\",
        \"category\": \"RemoteTool\",
        \"target\": \"${MCP_ENDPOINT}\",
        \"isSharedToAll\": true,
        \"audience\": \"https://search.azure.com/\",
        \"metadata\": { \"ApiType\": \"Azure\" }
      }
    }" | python3 -m json.tool || true
  echo "✓ Foundry connection created: $connection_name"
}

# ─── 3. Minimal knowledge source + knowledge base ─────────────────────────────
create_blob_ks "$MINIMAL_KS_NAME" "minimal"
create_kb "$MINIMAL_KB_NAME" "$MINIMAL_KS_NAME" \
  "Fibey IQ CU demo — minimal mode (standard text extraction, free tier)"

# ─── 4. Standard knowledge source + knowledge base ────────────────────────────
create_blob_ks "$STANDARD_KS_NAME" "standard"
create_kb "$STANDARD_KB_NAME" "$STANDARD_KS_NAME" \
  "Fibey IQ CU demo — standard mode (Azure Content Understanding, advanced table parsing)"

# ─── 5. Foundry connections ────────────────────────────────────────────────────
create_foundry_connection "$MINIMAL_CONNECTION_NAME"  "$MINIMAL_KB_NAME"
create_foundry_connection "$STANDARD_CONNECTION_NAME" "$STANDARD_KB_NAME"

# ─── 6. RBAC ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Assigning Search Index Data Reader RBAC ==="
ROLE_DEFINITION_ID="/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleDefinitions/${SEARCH_INDEX_DATA_READER_ROLE_ID}"

EXISTING=$(az role assignment list \
  --assignee-object-id "$FOUNDRY_MI_PRINCIPAL_ID" \
  --scope "$SEARCH_RESOURCE_ID" \
  --query "[?roleDefinitionId=='${ROLE_DEFINITION_ID}'].id | [0]" \
  -o tsv)

if [ -n "$EXISTING" ]; then
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

# ─── 7. Output ────────────────────────────────────────────────────────────────
MINIMAL_MCP="${SEARCH_ENDPOINT}/knowledgebases/${MINIMAL_KB_NAME}/mcp"
STANDARD_MCP="${SEARCH_ENDPOINT}/knowledgebases/${STANDARD_KB_NAME}/mcp"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Foundry IQ CU Demo setup complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Knowledge bases:"
echo "  Minimal  : ${MINIMAL_MCP}"
echo "  Standard : ${STANDARD_MCP}"
echo ""
echo "Add to your .env (or 'azd env set'):"
echo ""
echo "  FOUNDRY_IQ_MINIMAL_MCP_URL=\"${MINIMAL_MCP}\""
echo "  FOUNDRY_IQ_STANDARD_MCP_URL=\"${STANDARD_MCP}\""
echo ""
echo "Or with azd:"
echo "  azd env set FOUNDRY_IQ_MINIMAL_MCP_URL  \"${MINIMAL_MCP}\""
echo "  azd env set FOUNDRY_IQ_STANDARD_MCP_URL \"${STANDARD_MCP}\""
echo ""
echo "NOTE: The standard knowledge source uses contentExtractionMode=standard."
echo "      Indexing may take a few minutes. Check status with:"
echo "      curl -s \"${SEARCH_ENDPOINT}/knowledgesources/${STANDARD_KS_NAME}/indexers/status?api-version=${KNOWLEDGE_API_VERSION}\" -H \"api-key: \$AZURE_SEARCH_ADMIN_KEY\""
