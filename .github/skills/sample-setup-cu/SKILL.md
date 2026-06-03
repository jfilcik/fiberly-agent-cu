---
name: "CU Local-Direct Setup"
description: "Guide users through end-to-end setup for Content Understanding demo flows in local-direct mode, including Foundry IQ dual-ingestion wiring and analyzer creation."
tags: ['azure', 'content-understanding', 'foundry-iq', 'local-direct', 'setup', 'demo']
---

# CU Local-Direct Setup Skill

You are the setup specialist for enabling **Content Understanding (CU)** demo functionality in this repository using **AGENT_MODE=local-direct**.

Your goal is to produce a safe, explicit, user-approved setup flow that covers:
- CU prerequisites in Azure
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

## Step-by-step workflow

### 1) Local bootstrap (required)

Before CU-specific setup, ensure local dependencies and env file are prepared.

Ask permission to run:

```bash
./scripts/setup.sh
cp .env.example .env
```

Explain why:
- `./scripts/setup.sh` installs Python and UI dependencies used by local-direct demo runs.
- `cp .env.example .env` ensures there is a writable local env file for CU endpoint and MCP URL updates.

If `.env` already exists, keep the existing file and only update required keys.

### 2) CU prerequisites check (required)

Ask the user to complete Azure CU prerequisites first using the official document:

- https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/quickstart/use-rest-api?tabs=portal%2Cdocument&pivots=programming-language-rest#prerequisites

Use this exact check question:

"Have you completed the CU prerequisites from the Microsoft Learn quickstart (resource, access, and permissions)?"

If not done, pause and ask the user to finish prerequisites first.

### 3) CU endpoint in `.env`

Explain:
- `AZURE_CONTENTUNDERSTANDING_ENDPOINT` enables CU upload parsing in the chat flow and reveals CU UI controls.

Ask permission before editing:

"Do you want me to update `.env` with your `AZURE_CONTENTUNDERSTANDING_ENDPOINT` now?"

If the user approves, update `.env`. If missing, ask for endpoint value.

Optional companion variable when needed for setup tooling:
- `AZURE_CONTENTUNDERSTANDING_KEY`

### 4) Foundry IQ endpoint readiness check

Ask:

"Do you already have Foundry IQ / Foundry project endpoint configured (`FOUNDRY_PROJECT_ENDPOINT` and related Azure resources)?"

If not configured, ask:

"Do you want me to run `azd up` to provision/update the required Azure resources first?"

If approved, run `azd up` and continue after success.

### 5) Run CU KB setup (`--cu-demo`) and explain why

Ask permission to run:

`./scripts/setup-knowledge-base.sh --cu-demo`

Explain why before running:
- It uploads both base Foundry IQ docs and CU demo docs.
- It creates two ingestion paths:
  - minimal extraction (`fibey-iq-minimal-kb`)
  - standard CU extraction (`fibey-iq-standard-kb`)
- It outputs two MCP URLs used by the UI ingestion mode selector.

After run, ensure these are configured in environment:
- `FOUNDRY_IQ_MINIMAL_MCP_URL`
- `FOUNDRY_IQ_STANDARD_MCP_URL`

### 6) Verify two ingestion indexes are up

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

### 7) Create CU analyzers and explain demo impact

Ask permission to run analyzer creation:

```bash
uv run python content-understanding/tools/create_work_order_analyzer.py \
  --analyze content-understanding/demo_files/work_order_fiber_splice.pdf

uv run python content-understanding/tools/create_classify_and_analyze.py \
  --analyze content-understanding/demo_files/work_order_fiber_splice.pdf
```

Explain what this enables in demo:
- `cu_demo_work_order`: extracts structured work-order fields aligned to Fibey schema.
- `cu_demo_classify_and_analyze`: classifies uploads and routes work orders to structured extraction, other docs to layout extraction.
- This powers the CU mode comparison in the UI (`None`, `Basic CU`, `Classify & Analyze Work Order`).

### 8) Start local-direct stack with permission

Ask permission to start all required local services.

Start services (separate terminals/processes):

```bash
cd services/inventory-mcp && uv sync && uv run python server.py
cd services/work-orders-api && uv sync && uv run python server.py
cd services/status-dashboard/public && python -m http.server 8003
AGENT_MODE=local-direct ./scripts/start-dev.sh
```

### 9) Health and feature checks

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