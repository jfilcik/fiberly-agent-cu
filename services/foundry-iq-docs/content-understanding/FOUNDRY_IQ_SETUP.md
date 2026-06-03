# Foundry IQ CU Demo Setup

This guide sets up the **Foundry IQ Ingestion Mode demo** for Fibey Field Ops. The demo shows how two different `contentExtractionMode` settings in Azure AI Search produce different results when asked about tables in PDF documents — specifically tables with adjacent numeric columns and sparse (empty) cells.

## What the demo shows

| Mode | Setting | Parser | Table accuracy |
|------|---------|--------|----------------|
| **Minimal** | `contentExtractionMode: minimal` | Standard text extraction (free) | Empty cells collapse → column values shift left → wrong answers |
| **Standard** | `contentExtractionMode: standard` | Azure Content Understanding | Preserves cell boundaries → correct answers |

### Demo questions to try

After switching the **Foundry IQ Ingestion** mode in the sidebar:

**Primary demo question (OTDR report):**
> *"Check the KB — what is the ORL reading at 1310nm for fiber F-03?"*

| Mode | Expected answer | Why |
|------|----------------|-----|
| **Minimal** | ~46.1 dB *(wrong — this is the ORL @1550nm value)* | Blank ORL@1310 cell is collapsed; 46.1 shifts left into the 1310nm column |
| **Standard** | ORL@1310 was not recorded (blank) | HTML `<td></td>` preserves the empty cell; LLM correctly reads it as absent |

## Prerequisites

- Azure subscription with:
  - Azure AI Search service (Basic tier or above)
  - Azure Storage Account
  - Azure AI Foundry account + project
- Azure CLI installed and authenticated (`az login`)
- `azd` CLI installed (optional — used to read output values)
- `uv` installed (for generating demo PDFs)

## Step 1 — Verify demo documents

The CU demo document is versioned in this repo at:

`services/foundry-iq-docs/content-understanding/docs/otdr-acceptance-results.pdf`

Ensure this file exists before setup.

This document contains:

- **`otdr-acceptance-results.pdf`** — OTDR acceptance test table with 6 adjacent numeric columns (loss @1310, loss @1550, ORL @1310, ORL @1550) and sparse ORL cells

## Step 2 — Run the setup script

Run the KB setup script with `--cu-demo`.

```bash
export AZURE_RESOURCE_GROUP="<your-resource-group>"
export FOUNDRY_RESOURCE_GROUP="<your-foundry-resource-group>"
export FOUNDRY_ACCOUNT_NAME="<your-foundry-account>"

# Optional: only needed for standard mode with a dedicated AI Services endpoint
# export AZURE_CONTENTUNDERSTANDING_ENDPOINT="https://<your-ai-services>.cognitiveservices.azure.com/"
# export AZURE_CONTENTUNDERSTANDING_KEY="<your-key>"

./scripts/setup-knowledge-base.sh --cu-demo
```

Or pass the Foundry arguments directly:

```bash
./scripts/setup-knowledge-base.sh --cu-demo <foundry-rg> <foundry-account> <foundry-project>
```

The script will:

1. Create a blob container `foundry-iq-cu-demo` and upload both document sets:
  - Base FoundryIQ docs from `services/foundry-iq-docs/docs/`
  - CU demo docs from `services/foundry-iq-docs/content-understanding/docs/`
2. Create knowledge source `fibey-iq-minimal-ks` with `contentExtractionMode: minimal`
3. Create knowledge source `fibey-iq-standard-ks` with `contentExtractionMode: standard`
4. Create knowledge bases `fibey-iq-minimal-kb` and `fibey-iq-standard-kb`
5. Create Foundry connections `kb-fibey-iq-minimal` and `kb-fibey-iq-standard`
6. Assign Search Index Data Reader RBAC to the Foundry managed identity

This means CU mode keeps the original KB demo scenarios available while adding CU-specific table extraction scenarios.

> **Note:** `contentExtractionMode` cannot be changed after a knowledge source is created. If you need to change it, delete the knowledge source and recreate it.

## Step 3 — Configure your environment

The script prints the MCP endpoints at the end. Add them to your `.env`:

```bash
FOUNDRY_IQ_MINIMAL_MCP_URL="https://<search>.search.windows.net/knowledgebases/fibey-iq-minimal-kb/mcp"
FOUNDRY_IQ_STANDARD_MCP_URL="https://<search>.search.windows.net/knowledgebases/fibey-iq-standard-kb/mcp"
AZURE_SEARCH_ADMIN_KEY="<your-search-admin-key>"
```

Or with azd:

```bash
azd env set FOUNDRY_IQ_MINIMAL_MCP_URL  "https://..."
azd env set FOUNDRY_IQ_STANDARD_MCP_URL "https://..."
azd env set AZURE_SEARCH_ADMIN_KEY       "<your-search-admin-key>"
```

The admin key is used by the gateway to authenticate the KB MCP calls in local mode. Get it from the Azure portal under your Search service → **Keys**, or:

```bash
az search admin-key show --service-name <search-service> --resource-group <rg> --query primaryKey -o tsv
```

When both MCP URL variables are set, the **Foundry IQ Ingestion** selector appears in the Activity sidebar.

## Step 4 — Wait for indexing

The `standard` mode knowledge source uses Azure Content Understanding and takes longer to index (typically 2–5 minutes per document). Check indexer status using the **indexer name** (formed as `<ks-name>-indexer`):

```bash
SEARCH_ENDPOINT="https://<search>.search.windows.net"
curl -s "${SEARCH_ENDPOINT}/indexers/fibey-iq-standard-ks-indexer/status?api-version=2024-07-01" \
  -H "api-key: $AZURE_SEARCH_ADMIN_KEY" | python3 -m json.tool
```

Look for `"lastResult": { "status": "success", "itemsProcessed": 2 }` before running the demo.

## Architecture

```
UI sidebar (Foundry IQ Ingestion selector)
  └─ minimal / standard toggle
       ↓
App.tsx → useChat → sendMessage (foundry_iq_mode param)
       ↓
FastAPI Gateway /api/chat (foundry_iq_mode field)
       ↓
agent.py create_agent(foundry_iq_mode=...)
       ↓
MCPStreamableHTTPTool (FOUNDRY_IQ_MINIMAL_MCP_URL or FOUNDRY_IQ_STANDARD_MCP_URL)
       ↓
Azure AI Search Knowledge Base MCP
  ├─ fibey-iq-minimal-kb  ← contentExtractionMode: minimal
  └─ fibey-iq-standard-kb ← contentExtractionMode: standard
       ↓
Azure Blob Storage (foundry-iq-cu-demo container)
  └─ otdr-acceptance-results.pdf
```

## Troubleshooting

**The sidebar selector does not appear**
: Both `FOUNDRY_IQ_MINIMAL_MCP_URL` and `FOUNDRY_IQ_STANDARD_MCP_URL` must be set. Check `GET /api/features` — `foundry_iq_cu_demo` should be `true`.

**Both modes return the same answer**
: The standard knowledge source may still be indexing. Wait a few minutes and check indexer status (see Step 4). Also verify both URLs point to different KB names (`fibey-iq-minimal-kb` vs `fibey-iq-standard-kb`).

**Authentication errors from the KB MCP (`api-key` header)**
: Set `AZURE_SEARCH_ADMIN_KEY` in your `.env`. In local mode the gateway uses this key to authenticate directly to the Search MCP endpoint. The hosted mode uses the Foundry project managed identity instead (set up by the Foundry connection).

**Standard mode `contentExtractionMode` rejected (HTTP 400)**
: The search service managed identity needs `Cognitive Services User` on your AI Services account. The setup script assigns this, but IAM propagation can take 5–15 minutes. Alternatively, pass `AZURE_CONTENTUNDERSTANDING_KEY` so the script uses API-key auth instead of managed identity.

**Standard mode returns "no results"**
: Verify that the indexer completed successfully (see Step 4). If `contentExtractionMode: standard` was set without a valid `aiServices.uri`, the indexer fails silently — delete and recreate the knowledge source:
```bash
SEARCH_ADMIN_KEY="..." SEARCH_ENDPOINT="https://<search>.search.windows.net"
curl -X DELETE "${SEARCH_ENDPOINT}/knowledgesources/fibey-iq-standard-ks?api-version=2026-04-01" \
  -H "api-key: ${SEARCH_ADMIN_KEY}"
# Then re-run the setup script with AZURE_CONTENTUNDERSTANDING_ENDPOINT and AZURE_CONTENTUNDERSTANDING_KEY set
```
