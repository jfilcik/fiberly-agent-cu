# Module: CU Endpoint + Analyzers (Demos 1 + 2)

Loaded by `sample-setup-cu` at Stage 6 when `path` includes `1+2 only`
or `all three`.

## Scope (narrow)

Resources this module configures:
- 1 chat model deployment on the Foundry account (`gpt-4o-mini` default)
- 2 CU analyzers in the CU data plane:
  - `cu_demo_work_order`
  - `cu_demo_classify_and_analyze`

`.env` keys this module writes:
- `AZURE_CONTENTUNDERSTANDING_ENDPOINT`
- `FOUNDRY_PROJECT_ENDPOINT`
- `FOUNDRY_MODEL`
- `AZURE_AI_MODEL_DEPLOYMENT_NAME`

Does **NOT** touch: Storage, AI Search, Foundry IQ KB (that's
`foundry-iq-kb.md`), Container Apps / hosted runtime (out of scope).

## Required roles (verify, do not assign)

Already classified by orchestrator. If `track == dev`:

| Scope | Role |
|---|---|
| Foundry account | `Cognitive Services User` (CU + LLM data plane) |
| Foundry project | `Azure AI User` (model deployment listing + agent runtime) |

If `track == admin`, can additionally provision the model deployment via
ARM. If `track == none`, stop and emit `admin-request-block.md`.

## Steps

### Step 1 — Verify CU endpoint reachability (dev probe)

Compute CU endpoint from Foundry account:
```
AZURE_CONTENTUNDERSTANDING_ENDPOINT=https://<foundryAccountName>.services.ai.azure.com/
```

Probe (list analyzers, read-only):
- **Bash**:
  ```bash
  TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)
  curl -sS -H "Authorization: Bearer $TOKEN" \
    "${AZURE_CONTENTUNDERSTANDING_ENDPOINT}contentunderstanding/analyzers?api-version=2024-12-01-preview"
  ```
- **PowerShell**:
  ```powershell
  $token = az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
  Invoke-RestMethod -Headers @{Authorization = "Bearer $token"} `
    -Uri "$($env:AZURE_CONTENTUNDERSTANDING_ENDPOINT)contentunderstanding/analyzers?api-version=2024-12-01-preview"
  ```

If 401/403: load `admin-request-block.md` and emit it verbatim with the
failing role (`Cognitive Services User` on the Foundry account) pre-
filled. Do not improvise an ask-admin message. Stop after emitting.

### Step 2 — Verify or create chat model deployment

Discover existing deployments:
```
az cognitiveservices account deployment list \
  --name <foundryAccountName> --resource-group <foundryResourceGroup> -o table
```

If at least one chat deployment exists, ask the user which to use.

If none exists:
- **Admin track**: ask permission, then create:
  ```
  az cognitiveservices account deployment create \
    --name <foundryAccountName> --resource-group <foundryResourceGroup> \
    --deployment-name gpt-4o-mini \
    --model-format OpenAI --model-name gpt-4o-mini --model-version 2024-07-18 \
    --sku-name GlobalStandard --sku-capacity 50
  ```
- **Dev track**: stop. Provide the line above for the admin and exit.

Persist:
```
FOUNDRY_MODEL=<deployment>
AZURE_AI_MODEL_DEPLOYMENT_NAME=<deployment>
```

### Step 3 — Write `.env`

Confirm with the user before writing:
- `AZURE_CONTENTUNDERSTANDING_ENDPOINT`
- `FOUNDRY_PROJECT_ENDPOINT`
- `FOUNDRY_MODEL`
- `AZURE_AI_MODEL_DEPLOYMENT_NAME`

Use idempotent upsert (preserve other keys).

### Step 4 — Create CU analyzers

Confirm, then run (cross-platform — uv is shell-agnostic):
```
uv run python content-understanding/tools/create_work_order_analyzer.py
uv run python content-understanding/tools/create_classify_and_analyze.py
```

If either fails with 401/403: load `admin-request-block.md` and emit it
with the failing role pre-filled (`Cognitive Services User` on Foundry
account for CU 403; `Azure AI User` on the project for model-deployment-
list 403). Stop after emitting.

### Step 5 — Hand back to orchestrator

Report success + env keys written + analyzers created. The orchestrator
decides whether to chain into `foundry-iq-kb.md` (Demo 3) or stop here.

## Cross-platform rules

- OS already detected by orchestrator. Emit only the matching shell.
- Windows: pure built-in PowerShell. **Never** suggest Git Bash or WSL.
- Path separators: prefer `/` for cross-shell tools (`az`, `uv`, `python`).
