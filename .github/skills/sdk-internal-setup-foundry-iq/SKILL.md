---
name: "SDK Internal — Foundry IQ Setup"
description: "Internal sub-skill that configures Foundry IQ KB (Storage + AI Search + connections) for Demo 3. Invoked by sample-setup after sdk-internal-setup-cu. Do not invoke directly."
tags: ['internal', 'content-understanding', 'foundry-iq', 'knowledge-base', 'setup']
---

# sdk-internal-setup-foundry-iq

> ⚠ **Internal sub-skill.** If a user invoked this directly, stop and reply:
>
> > "This is an internal setup sub-skill. Please invoke the `sample-setup`
> > skill instead — it runs preflight (OS detect, role probe, region check)
> > and ensures `sdk-internal-setup-cu` ran first. Re-run with `/sample-setup`."

## Inputs (from orchestrator)

Assumes `sample-setup` has run preflight and `sdk-internal-setup-cu` has
completed. Inherits:

- `os`, `subscriptionId`, `tenantId`
- `foundryAccountName`, `foundryProjectEndpoint`, `foundryResourceGroup`
- `storageAccountName` (provisioned by `infra/main.bicep` with
  `includeFoundryIq=true`, or pre-existing)
- `searchServiceName` (same)
- `azureResourceGroup`
- `track` — `admin` / `dev` / `mixed`

If any missing, stop and tell user to re-run `sample-setup`.

## Scope (narrow)

Resources this skill configures (KB-only):
- 1 blob container (`foundry-iq-cu-demo`) populated with base + CU demo docs
- 2 Search knowledge sources (`fibey-iq-minimal-ks`, `fibey-iq-standard-ks`)
- 2 Search knowledge bases (`fibey-iq-minimal-kb`, `fibey-iq-standard-kb`)
- 2 Foundry project connections (one per KB)

`.env` keys this skill writes:
- `FOUNDRY_IQ_MINIMAL_MCP_URL`
- `FOUNDRY_IQ_STANDARD_MCP_URL`
- `AZURE_SEARCH_ENDPOINT`
- `AZURE_SEARCH_INDEX`

What this skill does **NOT** touch:
- CU endpoint / analyzers (owned by `sdk-internal-setup-cu`)
- Container Apps / hosted runtime

## Required roles

| Scope | Role | Track required |
|---|---|---|
| Storage account | `Storage Blob Data Contributor` | dev |
| Search service | `Search Index Data Contributor` | dev |
| Foundry project | `Azure AI User` | dev (to create connection) |
| Resource group | `Reader` | dev (to discover endpoints) |
| Search service | `User Access Administrator` | **admin only**, for Foundry MI role assignment |

**No `Storage Account Contributor`, no `Search Service Contributor`, no
`listKeys` rights needed for dev track** — script uses data-plane auth
(`--auth-mode login`, AAD Bearer tokens).

## Steps

### Step 1 — Verify data-plane access (dev probes)

Run three probes before any mutation:

**Storage** (Bash / PowerShell):
```
az storage container list --account-name <storage> --auth-mode login -o table
```
Failure → ask admin for `Storage Blob Data Contributor` on storage. Stop.

**Search** (need AAD enabled on Search service first; see Step 1a):
- **Bash**:
  ```bash
  TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)
  curl -sS -H "Authorization: Bearer $TOKEN" \
    "https://<search>.search.windows.net/servicestats?api-version=2024-07-01"
  ```
- **PowerShell**:
  ```powershell
  $token = az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
  Invoke-RestMethod -Headers @{Authorization = "Bearer $token"} `
    -Uri "https://<search>.search.windows.net/servicestats?api-version=2024-07-01"
  ```
Failure → ask admin for `Search Index Data Contributor` on Search. Stop.

### Step 1a — (Admin only) Enable AAD auth on Search

Once per service. Skip if already done.

```
az search service update --name <search> --resource-group <rg> --auth-options aad
```

Dev track: surface this command for admin to run. Stop until done.

### Step 2 — Run KB setup script

Confirm with user, then run with explicit env injection:

- **Bash**:
  ```bash
  AZURE_RESOURCE_GROUP="<rg>" \
  AZURE_SUBSCRIPTION_ID="<sub>" \
  FOUNDRY_PROJECT_ENDPOINT="<endpoint>" \
  ./scripts/setup-knowledge-base.sh --cu-demo
  ```
- **PowerShell** (when `.ps1` sibling lands — currently uses Bash):
  ```powershell
  $env:AZURE_RESOURCE_GROUP = "<rg>"
  $env:AZURE_SUBSCRIPTION_ID = "<sub>"
  $env:FOUNDRY_PROJECT_ENDPOINT = "<endpoint>"
  ./scripts/setup-knowledge-base.ps1 -CuDemo
  ```
  > Note: `.ps1` port is a follow-up. Until then, Windows users without
  > PowerShell-native script must wait or use Azure Cloud Shell. Do NOT
  > tell them to install Git Bash / WSL.

The script uses `--auth-mode login` and AAD Bearer tokens — no `listKeys`,
no admin-key.

### Step 3 — (Admin only) Assign Foundry MI's KB role

Once per Foundry account. Skip if already done.

```bash
./scripts/setup-knowledge-base.sh --admin-prep
```

This assigns `Search Index Data Reader` to the Foundry project MI on the
Search service. Without this, KB MCP queries from the agent will 403.

Dev track: surface this command for admin to run if KB queries fail.

### Step 4 — Verify both indexers reach `success`

```
SEARCH_ENDPOINT=https://<search>.search.windows.net
TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

for IDX in fibey-iq-minimal-ks-indexer fibey-iq-standard-ks-indexer; do
  curl -sS -H "Authorization: Bearer $TOKEN" \
    "${SEARCH_ENDPOINT}/indexers/$IDX/status?api-version=2024-07-01" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['name'], d.get('lastResult',{}).get('status','running'))"
done
```

Standard mode can take several minutes (CU extraction).

### Step 5 — Persist `.env`

Write:
- `FOUNDRY_IQ_MINIMAL_MCP_URL=https://<search>.search.windows.net/knowledgebases/fibey-iq-minimal-kb/mcp`
- `FOUNDRY_IQ_STANDARD_MCP_URL=https://<search>.search.windows.net/knowledgebases/fibey-iq-standard-kb/mcp`
- `AZURE_SEARCH_ENDPOINT=https://<search>.search.windows.net`

### Step 6 — Hand control back to orchestrator

Report back to `sample-setup`:
- `success: true`
- `envWritten: [FOUNDRY_IQ_MINIMAL_MCP_URL, FOUNDRY_IQ_STANDARD_MCP_URL, AZURE_SEARCH_ENDPOINT]`
- `indexers: { minimal: <status>, standard: <status> }`

Orchestrator handles "next steps" messaging (start gateway, point user to
`sample-demo-cu`).

## Cross-platform rules

- OS detected by orchestrator. Emit only the matching shell.
- Windows: pure built-in PowerShell. **Never** suggest Git Bash or WSL.
- Region mismatch (Storage in region X, Search in region Y, Foundry in
  region Z) is **expected and supported** — informational note only, do
  not block.
