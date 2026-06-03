---
name: "CU Local-Direct Setup"
description: "Guide users through end-to-end setup for Content Understanding demo flows in local-direct mode, including Foundry IQ dual-ingestion wiring and analyzer creation."
tags: ['azure', 'content-understanding', 'foundry-iq', 'local-direct', 'setup', 'demo']
---

# CU Local-Direct Setup Skill

You are the setup specialist for enabling **Content Understanding (CU)** demo functionality in this repository using **AGENT_MODE=local-direct**.

Your goal is to produce a safe, explicit, user-approved setup flow that covers:
- Azure CLI (`az`) and Azure Developer CLI (`azd`) availability checks
- installation guidance when `az`/`azd` is missing
- Azure subscription and active subscription context checks
- CU resource readiness checks
- CU prerequisites in Azure
- guided CU prerequisite completion with direct CU Studio settings link
- `.env` updates for CU and Foundry IQ CU demo endpoints
- optional Azure provisioning via `azd up`
- CU demo KB ingestion setup (`--cu-demo`)
- CU analyzer creation
- local-direct startup and health checks
- guided demo scenarios

## Scope and intent

Use this skill when the user asks to:
- set up CU locally
- enable file upload CU scenarios
- configure Foundry IQ minimal vs standard ingestion demo
- run the CU demo end to end in local-direct mode

Prefer this skill over ad hoc instructions because it enforces permission gates and checks every required dependency.

## Ground truth (repo-specific)

- Local-direct is the recommended mode for CU iteration (`AGENT_MODE=local-direct`).
- CU chat-time parsing is enabled by `AZURE_CONTENTUNDERSTANDING_ENDPOINT`.
- Foundry IQ dual-ingestion toggle is enabled only when both are set:
  - `FOUNDRY_IQ_MINIMAL_MCP_URL`
  - `FOUNDRY_IQ_STANDARD_MCP_URL`
- CU KB setup flag in this repo is:
  - `./scripts/setup-knowledge-base.sh --cu-demo`
- CU analyzers created by scripts:
  - `cu_demo_work_order`
  - `cu_demo_classify_and_analyze`

## Mandatory user confirmation gates

You must ask and wait for user confirmation before each action group:

1. Edit `.env` values.
2. Run Azure provisioning (`azd up`) when Foundry IQ endpoint/config is missing.
3. Run KB setup scripts that create cloud resources/connections.
4. Create/recreate CU analyzers.
5. Start local services in local-direct mode.

When available, use the ask-user tool (`vscode_askQuestions`) for these
confirmations instead of plain text prompts.

Use `vscode_askQuestions` for all major Yes/No checkpoints in this skill,
including subscription selection, CU prerequisites completion, `.env` edits,
`azd up`, KB setup, analyzer creation, and local startup.

Recommended options for each confirmation:
- `Yes, continue`
- `No, stop here`

For all user choices, always include an additional option such as:
- `Other (specify)`

And set `allowFreeformInput: true` so users can provide extra context,
alternative values, or custom paths.

## Why-first interaction rule (required)

Before any user choice, first explain **why the step is needed** in 1-2 clear
sentences, then ask for confirmation.

Use this format for every gated step:
1. `Why this step is needed:` <brief rationale tied to demo outcome>
2. `What will run/change:` <exact command or file/env side effect>
3. Ask with `vscode_askQuestions` (`Yes, continue` / `No, stop here` / `Other (specify)`).

Step rationale checklist (must be stated before asking):
- Step 0 (CLI preflight): ensures required Azure tooling exists before any setup work.
- Step 1 (subscription): ensures actions run in the intended Azure subscription.
- Step 2 (CU resource + Studio): ensures CU backend and model wiring are configured.
- Step 3 (prerequisites confirmation): prevents proceeding with missing RBAC/resource prerequisites.
- Step 4 (local bootstrap): prepares local dependencies and baseline env file.
- Step 5 (`.env` CU endpoint): enables CU upload parsing and CU mode controls.
- Step 6 (Foundry endpoint readiness): ensures Foundry project context exists before KB setup.
- Step 7 (KB setup): creates minimal/standard ingestion paths and MCP endpoints.
- Step 8 (indexer verification): confirms both ingestion paths are actually ready.
- Step 9 (analyzers): enables custom work-order extraction and classify+route demo mode.
- Step 10 (local-direct startup): starts runtime services required for end-to-end testing.
- Step 11 (health/features): validates local-direct mode and CU feature flags are active.

## Step-by-step workflow

Before step 1, give a brief CU intro using README-aligned language:

"Azure Content Understanding (CU) is a multimodal understanding capability for extracting structure and meaning from diverse formats and layouts. CU can also process audio/video, but this demo focuses on document modalities. This fork uses CU to improve upload parsing, classification/routing, and structured extraction quality in the local-direct flow."

Keep this intro to 2-3 sentences max, then continue with the checks.

### 0) CLI preflight: `az` and `azd` (required)

Before Azure checks, verify required CLIs are available:

```bash
command -v az >/dev/null && az version || echo "az missing"
command -v azd >/dev/null && azd version || echo "azd missing"
```

If either CLI is missing, stop and provide installation guidance first.

macOS install guidance:
- Azure CLI (`az`): `brew update && brew install azure-cli`
- Azure Developer CLI (`azd`): `brew tap azure/azd && brew install azd`

Verify after install:

```bash
az version
azd version
```

Only continue to Azure subscription/CU setup after both commands succeed.

### 1) Azure subscription check (required)

Before any CU setup, verify the user has an active Azure subscription and that
the intended subscription is selected.

Use read-only checks:

```bash
az account show --output table
az account list --output table
```

Ask:

"Do you want to use the currently active subscription for CU setup?"

Prefer asking this via `vscode_askQuestions`.

If no active subscription is available, stop and instruct the user to:
- sign in: `az login`
- create or enable a subscription:
  https://azure.microsoft.com/pricing/purchase-options/azure-account

### 2) CU resource + CU Studio settings readiness (required)

Verify CU-related resources exist in the selected subscription.

Suggested checks:

```bash
az cognitiveservices account list --output table
```

Do not only paste links. First summarize the CU prerequisites from the official source in a short checklist, then provide links.

Use this prerequisite summary (concise but explicit):
- Active Azure subscription.
- A Microsoft Foundry resource in a CU-supported region.
- Sufficient RBAC to create/configure resources (Contributor or higher on target subscription/resource group).
- CU Studio settings configured to connect the target Foundry resource.
- Required model defaults configured; keep "Enable autodeployment for required models" on.

Then provide links in this order:

1. Prerequisites source:
  https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/quickstart/use-rest-api?tabs=portal%2Cdocument&pivots=programming-language-rest#prerequisites
2. CU Studio settings (direct):
  https://contentunderstanding.ai.azure.com/settings

Tell the user what to verify in CU Studio settings:
- Add/select the Foundry resource used for CU.
- Save settings.
- Keep "Enable autodeployment for required models" enabled.

Use this check question:

"Can you confirm CU Studio settings are configured for your target Foundry resource?"

Prefer asking this via `vscode_askQuestions`.

If not done, pause and ask the user to complete this before continuing.

### 3) CU prerequisites completion check (required)

Before asking for confirmation, restate the short prerequisite checklist above so
the user can verify each item without opening multiple pages.

Use this exact check question:

"Have you completed the CU prerequisites from the Microsoft Learn quickstart (resource, access, and permissions)?"

Prefer asking this via `vscode_askQuestions`.

If not done, pause and ask the user to finish prerequisites first.

### 4) Local bootstrap (required)

Before CU-specific setup, ensure local dependencies and env file are prepared.

Ask permission to run:

```bash
./scripts/setup.sh
cp .env.example .env
```

Prefer asking this via `vscode_askQuestions`.

Explain why:
- `./scripts/setup.sh` installs Python and UI dependencies used by local-direct demo runs.
- `cp .env.example .env` ensures there is a writable local env file for CU endpoint and MCP URL updates.

If `.env` already exists, keep the existing file and only update required keys.

### 5) CU endpoint in `.env`

Explain:
- `AZURE_CONTENTUNDERSTANDING_ENDPOINT` enables CU upload parsing in the chat flow and reveals CU UI controls.

Ask permission before editing:

"Do you want me to update `.env` with your `AZURE_CONTENTUNDERSTANDING_ENDPOINT` now?"

Prefer asking this via `vscode_askQuestions`.

If the user approves, update `.env`. If missing, ask for endpoint value.

Optional companion variable when needed for setup tooling:
- `AZURE_CONTENTUNDERSTANDING_KEY`

### 6) Foundry IQ endpoint readiness check

Why this step is needed (must explain before asking):
- `FOUNDRY_PROJECT_ENDPOINT` is required to attach Search MCP connections to the
  correct Foundry project. Without it, KB setup cannot create/update the
  project-side connections used by the demo.
- `./scripts/setup-knowledge-base.sh --cu-demo` will fail early if this value is
  missing.

When asking, always show candidate value(s) and ask the user to confirm or
provide another endpoint.

Suggested discovery commands:

```bash
azd env get-value FOUNDRY_PROJECT_ENDPOINT
az resource list --query "[?(type=='Microsoft.CognitiveServices/accounts/projects' || type=='Microsoft.MachineLearningServices/workspaces/projects')].[id]" -o table
```

If a candidate is found, ask:
- Confirm this endpoint, or provide another:
  `https://<account>.services.ai.azure.com/api/projects/<project>`

Ask:

"Do you already have Foundry IQ / Foundry project endpoint configured (`FOUNDRY_PROJECT_ENDPOINT` and related Azure resources)?"

If not configured, ask:

"Do you want me to run `azd up` to provision/update the required Azure resources first?"

Prefer asking this via `vscode_askQuestions`.

Include options:
- `Yes, continue`
- `No, stop here`
- `Other (specify endpoint or setup path)`

If the user doesn't have a project endpoint, provide these paths:
1. Provision/update via `azd provision` or `azd up`.
2. Attach to existing project via:
  `azd ai agent init --project-id <resource-id>`
3. Open Foundry portal and copy project endpoint, then paste it back.

If approved, run `azd up` and continue after success.

### 7) Run CU KB setup (`--cu-demo`) and explain why

Ask permission to run:

`./scripts/setup-knowledge-base.sh --cu-demo`

Prefer asking this via `vscode_askQuestions`.

Explain why before running:
- It uploads both base Foundry IQ docs and CU demo docs.
- It creates two ingestion paths:
  - minimal extraction (`fibey-iq-minimal-kb`)
  - standard CU extraction (`fibey-iq-standard-kb`)
- It outputs two MCP URLs used by the UI ingestion mode selector.

After run, ensure these are configured in environment:
- `FOUNDRY_IQ_MINIMAL_MCP_URL`
- `FOUNDRY_IQ_STANDARD_MCP_URL`

### 8) Verify two ingestion indexes are up

Check indexer states for both knowledge sources:
- `fibey-iq-minimal-ks-indexer`
- `fibey-iq-standard-ks-indexer`

Suggested command pattern:

```bash
SEARCH_ENDPOINT="https://<search>.search.windows.net"
curl -s "${SEARCH_ENDPOINT}/indexers/fibey-iq-minimal-ks-indexer/status?api-version=2024-07-01" \
  -H "api-key: $AZURE_SEARCH_ADMIN_KEY" | python3 -m json.tool

curl -s "${SEARCH_ENDPOINT}/indexers/fibey-iq-standard-ks-indexer/status?api-version=2024-07-01" \
  -H "api-key: $AZURE_SEARCH_ADMIN_KEY" | python3 -m json.tool
```

Interpretation guidance:
- `lastResult.status == success` is ready.
- standard mode can take longer due to CU extraction.

### 9) Create CU analyzers and explain demo impact

Ask permission to run analyzer creation:

```bash
uv run python content-understanding/tools/create_work_order_analyzer.py \
  --analyze content-understanding/demo_files/work_order_fiber_splice.pdf

uv run python content-understanding/tools/create_classify_and_analyze.py \
  --analyze content-understanding/demo_files/work_order_fiber_splice.pdf
```

Prefer asking this via `vscode_askQuestions`.

Explain what this enables in demo:
- `cu_demo_work_order`: extracts structured work-order fields aligned to Fibey schema.
- `cu_demo_classify_and_analyze`: classifies uploads and routes work orders to structured extraction, other docs to layout extraction.
- This powers the CU mode comparison in the UI (`None`, `Basic CU`, `Classify & Analyze Work Order`).

### 10) Start local-direct stack with permission

Ask permission to start all required local services.

Prefer asking this via `vscode_askQuestions`.

Start services (separate terminals/processes):

```bash
cd services/inventory-mcp && uv sync && uv run python server.py
cd services/work-orders-api && uv sync && uv run python server.py
cd services/status-dashboard/public && python -m http.server 8003
AGENT_MODE=local-direct ./scripts/start-dev.sh
```

### 11) Health and feature checks

Run and validate:

```bash
curl http://localhost:8080/api/health
curl http://localhost:8080/api/features
```

Expected:
- `/api/health` includes `"mode":"local-direct"`
- `/api/features` shows:
  - `content_understanding: true` when CU endpoint is set
  - `foundry_iq_cu_demo: true` when both Foundry IQ MCP URLs are set

## Demo scenarios to suggest after setup

Point users to `content-understanding/demo_files/` and suggest:

1. Mode `None` + `.docx` upload: show baseline limitation.
2. Mode `Basic CU`: extraction works but may miss domain-specific field semantics.
3. Mode `Classify & Analyze Work Order`: structured extraction with correct routing.
4. Foundry IQ Ingestion selector `minimal` vs `standard` for table-accuracy comparison.

## Communication style requirements

- Be explicit about what command will run and why.
- Call out side effects (resource creation, env changes, analyzer recreation).
- Never edit `.env` or run provisioning/setup scripts without user confirmation.
- If prerequisites are incomplete, stop and provide the exact next action.

## Standard ask-user templates

Use these templates for every decision point:

- Confirmation template:
  - Question: concise action question.
  - Options: `Yes, continue`, `No, stop here`, `Other (specify)`.
  - `allowFreeformInput: true`.

- Value confirmation template (for endpoints/IDs):
  - Show detected value(s) first.
  - Ask: "Use this value, or provide another?"
  - Options: `Use detected value`, `Provide another value`, `Stop here`.
  - `allowFreeformInput: true`.

## Reliability improvements from execution (apply by default)

- Prefer explicit env injection (`VAR=... command`) over `source .env` in shell
  to avoid shell parsing issues from comments/values.
- Before Step 10, check for local port conflicts (`8001`, `8002`, `8080`, `5173`)
  and explain whether existing services can be reused.
- Treat `./scripts/setup-knowledge-base.sh --cu-demo` as potentially non-idempotent
  on reruns. If rerun fails after partial success, recover by cleaning conflicting
  `fibey-iq-*` KB/KS/connection resources in dependency-safe order, then retry.
- If `azd up` fails with missing `AZURE_AI_PROJECT_ID`, guide to either:
  1) run `azd provision`, or
  2) connect to existing project via `azd ai agent init --project-id <resource-id>`.
- Analyzer creation failures should branch by error type:
  - RBAC/data-action denied: stop and request CU role assignment.
  - Key/identity mismatch: prefer key-based auth when key is configured.