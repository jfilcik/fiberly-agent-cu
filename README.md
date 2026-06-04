# Fibey Field Ops

> 🤖 **Using an AI coding assistant?** See [`AGENTS.md`](AGENTS.md) for the
> entry point. TL;DR: invoke the `sample-setup` skill.

This repository is a fork of https://github.com/dbarkol/fibey-agent.
The original Fibey demo showcases a fiber field-operations assistant that uses
an Azure AI Foundry agent with Toolbox-connected operational services.

Azure Content Understanding (CU) is a multimodal document understanding
capability for extracting structure and meaning from diverse document formats
and layouts.

CU can also process other modalities, including audio and video files.
This demo, however, focuses on document modalities and CU-powered document
workflows.

For official product details, see:

- https://learn.microsoft.com/azure/ai-services/content-understanding/overview

This fork is focused on one goal: demonstrating how Azure Content
Understanding (CU) improves the agent flow, especially in:

- document upload
    - Supports documents from different sources (photos, scans,
        screenshots), including `.docx`, handwritten text, and complex layout
        understanding.
- document classification
    - Routes each document to the right analyzer path, reducing incorrect tool
        usage and improving downstream behavior.
- document extraction quality
    - Improves structured field accuracy and consistency for downstream agent
        actions.
- Foundry IQ standard-mode ingestion
    - Preserves table structure and improves retrieval reliability for KB-backed
        answers.

## CU-focused scope in this fork

The original demo supports multiple runtime modes (see `AGENT_MODE`).
This fork focuses on `local-direct` mode: the gateway runs the agent in-process and
bypasses cloud-based Toolbox. Instead, backend services are launched locally,
and the agent calls local services directly to reduce cloud
setup complexity for the CU demo flow.

- CU-powered upload parsing in local-direct mode (agent + tool services running locally)
- CU custom analyzer workflow for work orders
- Foundry IQ ingestion comparison, with emphasis on standard mode (CU-enhanced)
- Demo-first setup flow through Copilot skill automation

## Architecture (CU demo path)

For the full-platform architecture from the original fork, see:

- https://github.com/dbarkol/fibey-agent#architecture

The diagram below shows this fork's `local-direct` mode.

```text
┌──────────────┐  /api/chat  ┌──────────────────┐  in-proc  ┌──────────────────┐
│  React UI    │ ──────────► │  FastAPI Gateway │ ────────► │  Fibey Agent     │
│  + Activity  │ ◄── SSE ─── │  (:8080)         │           │ (agent-framework)│
└──────────────┘             └──────────────────┘           └────────┬─────────┘
                               ┌─────────────────────────────────────────────┐
                               │                                             │
                local-direct calls to local services          queries cloud KB
                               │                                             │
                               ▼                                             ▼
                    ┌────────────────┬───────────────────┐    ┌─────────────────────────────────────────────────────────┐
                    │ inventory-mcp  │ work-orders-api   │    │ Foundry IQ (Cloud / AI Search)                         │
                    │   (:8001)      │    (:8002)        │    │  - minimal index: baseline ingestion                    │
                    └────────────────┴───────────────────┘    │  - standard index: CU-enhanced (better layout/tables)  │
                                                              └─────────────────────────────────────────────────────────┘

```

## Quickstart (recommended)

Use Copilot Chat command directly:

- `/sample-setup`

The skill will guide and execute (with your confirmation) the full CU demo setup:

1. Install dependencies and bootstrap local `.env`
2. Check CU prerequisites from Microsoft Learn
3. Update `.env` CU endpoint values
4. Confirm Foundry endpoint readiness (or offer `azd up`)
5. Run `./scripts/setup-knowledge-base.sh --cu-demo`
6. Verify both CU ingestion indexers are ready
7. Create CU demo analyzers
8. Start local-direct services and run health checks

After setup, open the UI:

- http://localhost:5173

Once setup is complete, run the interactive demo walkthrough:

- `/sample-demo-cu`

This skill drives three CU demos in order — Foundry IQ Minimal vs. Standard · Azure CU ingestion, agent upload modes (None → Parse: prebuilt-layout), and a Classify & Analyze Work Order deep dive — with manual steps and talking points for each.

## Prerequisites (minimum)

- Python 3.12+
- Node.js 20+
- [uv](https://docs.astral.sh/uv/) (Python package manager)

- Azure CLI (`az`)
- Azure Developer CLI (`azd`) when provisioning/updating Azure resources

## CU runtime expectations

The CU demo flow expects these variables to be configured:

| Variable | Purpose |
|---|---|
| `AZURE_CONTENTUNDERSTANDING_ENDPOINT` | Enables CU file upload parsing in chat |
| `FOUNDRY_IQ_MINIMAL_MCP_URL` | Foundry IQ minimal ingestion endpoint |
| `FOUNDRY_IQ_STANDARD_MCP_URL` | Foundry IQ standard (CU-enhanced) ingestion endpoint |

The `/sample-setup` skill sets up and verifies this flow.

## Local endpoints

| Service | Local URL |
|---|---|
| UI | `http://localhost:5173` |
| Gateway | `http://localhost:8080` |
| Inventory MCP | `http://localhost:8001` |
| Work Orders API | `http://localhost:8002` |

## CU demo references

| Doc | When to read it |
|---|---|
| [content-understanding/README.md](content-understanding/README.md) | End-to-end CU demo walkthrough and analyzer commands |
| [services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md](services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md) | Foundry IQ minimal vs standard ingestion setup details |
| [.github/skills/sample-setup/SKILL.md](.github/skills/sample-setup/SKILL.md) | Copilot skill playbook used by `/sample-setup` |
| [.github/skills/sample-demo-cu/SKILL.md](.github/skills/sample-demo-cu/SKILL.md) | Copilot skill playbook used by `/sample-demo-cu` to run the CU demo scenarios |

## Need the original full-platform guidance?

If you need detailed guidance on Toolbox integration, hosted agents,
container app deployment, and the broader original sample scope, use the
upstream repository:

- https://github.com/dbarkol/fibey-agent

## Project layout (CU-relevant)

```text
content-understanding/                                # CU demo files + analyzer tools
services/foundry-iq-docs/content-understanding/docs/  # Foundry IQ CU demo docs
scripts/setup-knowledge-base.sh                       # Creates minimal/standard CU demo KBs
src/fibey/gateway/                                    # API endpoints, feature flags, health checks
ui/src/                                               # Chat UI, KB extraction mode, and CU Context Provider selectors
```

## License

Licensed under the MIT License — see [LICENSE](LICENSE).
