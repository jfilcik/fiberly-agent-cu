# Module: Foundry IQ KB (Demo 3)

Loaded by `sample-setup-cu` at Stage 6 when `path` includes Demo 3,
**after** `cu-endpoint-and-analyzers.md` completes (or is skipped because
Demos 1+2 are already configured).

## Scope (narrow)

Resources this module configures (KB-only):
- 1 blob container (`foundry-iq-cu-demo`) populated with base + CU demo docs
- 2 Search knowledge sources (`fibey-iq-minimal-ks`, `fibey-iq-standard-ks`)
- 2 Search knowledge bases (`fibey-iq-minimal-kb`, `fibey-iq-standard-kb`)
- 2 Foundry project connections (one per KB)

`.env` keys this module writes:
- `FOUNDRY_IQ_MINIMAL_MCP_URL`
- `FOUNDRY_IQ_STANDARD_MCP_URL`
- `AZURE_SEARCH_ENDPOINT`
- `AZURE_SEARCH_INDEX`

Does **NOT** touch: CU endpoint / analyzers (`cu-endpoint-and-analyzers.md`
owns that), Container Apps / hosted runtime.

## Required roles

| Scope | Role | Track required |
|---|---|---|
| Storage account | `Storage Blob Data Contributor` | dev |
| Search service | `Search Index Data Contributor` | dev |
| Foundry project | `Azure AI User` | dev (to create connection) |
| Resource group | `Reader` | dev (recommended; convenience-only) |
| Search service | `User Access Administrator` | **admin only**, for Foundry MI role assignment |

No `Storage Account Contributor`, no `Search Service Contributor`, no
`listKeys` rights needed for dev track — script uses data-plane auth
(`--auth-mode login`, AAD Bearer tokens).

## Steps

### Step 1 — Verify data-plane access (dev probes)

Run two probes before any mutation:

**Storage** (cross-platform):
```
az storage container list --account-name <storage> --auth-mode login -o table
```
Failure → load `admin-request-block.md` and emit with `Storage Blob Data
Contributor` on storage pre-filled. Stop.

**Search** (needs AAD enabled on Search service first; see Step 1a):
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
Failure → load `admin-request-block.md` and emit with `Search Index Data
Contributor` on Search pre-filled (and add the "enable AAD auth" command
from Step 1a if it's also needed). Stop.

### Step 1a — (Admin only) Enable AAD auth on Search

Once per service. Skip if already done.

```
az search service update --name <search> --resource-group <rg> --auth-options aad
```

Dev track: load `admin-request-block.md` and emit it, adding the
`az search service update --auth-options aad` command above to the
admin's task list. Stop until admin confirms it's been run.

### Step 2 — Run KB setup script

Confirm with user, then run with explicit env injection:

- **Bash** (macOS / Linux):
  ```bash
  AZURE_RESOURCE_GROUP="<rg>" \
  AZURE_SUBSCRIPTION_ID="<sub>" \
  FOUNDRY_PROJECT_ENDPOINT="<endpoint>" \
  ./scripts/setup-knowledge-base.sh --cu-demo
  ```
- **PowerShell** (Windows):
  ```powershell
  $env:AZURE_RESOURCE_GROUP = "<rg>"
  $env:AZURE_SUBSCRIPTION_ID = "<sub>"
  $env:FOUNDRY_PROJECT_ENDPOINT = "<endpoint>"
  ./scripts/setup-knowledge-base.ps1 -CuDemo
  ```

The script uses `--auth-mode login` and AAD Bearer tokens — no `listKeys`,
no admin-key.

### Step 3 — (Admin only) Assign Foundry MI's KB role

Once per Foundry account. Skip if already done.

```
./scripts/setup-knowledge-base.sh --admin-prep        # macOS / Linux
./scripts/setup-knowledge-base.ps1 -AdminPrep         # Windows
```

This assigns `Search Index Data Reader` to the Foundry project MI on the
Search service. Without this, KB MCP queries from the agent will 403.

Dev track: load `admin-request-block.md` and emit it including the
`--admin-prep` line. This is the one-time `Search Index Data Reader`
assignment for the Foundry MI.

### Step 4 — Verify both indexers reach `success`

- **Bash**:
  ```bash
  SEARCH_ENDPOINT=https://<search>.search.windows.net
  TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

  for IDX in fibey-iq-minimal-ks-indexer fibey-iq-standard-ks-indexer; do
    curl -sS -H "Authorization: Bearer $TOKEN" \
      "${SEARCH_ENDPOINT}/indexers/$IDX/status?api-version=2024-07-01" \
      | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['name'], d.get('lastResult',{}).get('status','running'))"
  done
  ```
- **PowerShell**:
  ```powershell
  $endpoint = "https://<search>.search.windows.net"
  $token = az account get-access-token --resource https://search.azure.com --query accessToken -o tsv
  foreach ($idx in 'fibey-iq-minimal-ks-indexer','fibey-iq-standard-ks-indexer') {
    $r = Invoke-RestMethod -Headers @{Authorization = "Bearer $token"} `
      -Uri "$endpoint/indexers/$idx/status?api-version=2024-07-01"
    "$($r.name) $($r.lastResult.status)"
  }
  ```

Standard mode can take several minutes (CU extraction).

### Step 5 — Persist `.env`

Write (idempotent upsert):
- `FOUNDRY_IQ_MINIMAL_MCP_URL=https://<search>.search.windows.net/knowledgebases/fibey-iq-minimal-kb/mcp`
- `FOUNDRY_IQ_STANDARD_MCP_URL=https://<search>.search.windows.net/knowledgebases/fibey-iq-standard-kb/mcp`
- `AZURE_SEARCH_ENDPOINT=https://<search>.search.windows.net`

### Step 6 — Hand back to orchestrator

Report success + env keys written + indexer statuses. The orchestrator
handles "next steps" messaging (start gateway, point user to
`sample-demo-cu`).

## Cross-platform rules

- OS already detected by orchestrator. Emit only the matching shell.
- Windows: pure built-in PowerShell. **Never** suggest Git Bash or WSL.
- Region mismatch (Storage in region X, Search in region Y, Foundry in
  region Z) is **expected and supported** — informational note only,
  do not block.
