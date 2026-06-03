# Fibey Field Ops

Azure Content Understanding (CU) is a multimodal document understanding
capability for extracting structure and meaning from diverse document formats
and layouts.

For official product details, see:

- https://learn.microsoft.com/azure/ai-services/content-understanding/overview

This repository is a fork of:

- https://github.com/dbarkol/fibey-agent

This fork is focused on one goal: demonstrating how Azure Content
Understanding (CU) improves the agent flow, especially in:

- document upload
    - Supports a wide range of document types and capture styles, including
        `.docx`, scanned documents, handwritten text, and complex layout
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

- CU-powered upload parsing in local-direct mode
- CU custom analyzer workflow for work orders
- Foundry IQ ingestion comparison, with emphasis on standard mode (CU-enhanced)
- Demo-first setup flow through Copilot skill automation

## Architecture (CU demo path)

```text
┌──────────────┐  /api/chat  ┌──────────────────┐  in-proc  ┌──────────────────┐
│  React UI    │ ──────────► │  FastAPI Gateway │ ────────► │  Fibey Agent     │
│  + Activity  │ ◄── SSE ─── │  (:8080)         │           │  (agent-fw)      │
└──────────────┘             └──────────────────┘           └────────┬─────────┘
                                                                     │
                                                         Foundry Toolbox MCP
                                                                     │
              ┌────────────────┬───────────────────┬─────────────────┐
              │ inventory-mcp  │ work-orders-api   │ FoundryIQ KB    │
              │   (:8001)      │    (:8002)        │ (AI Search)     │
              └────────────────┴───────────────────┴─────────────────┘
```

The sample also ships **containerapp** and **hosted** modes — see
[docs/architecture.md](docs/architecture.md).

## Quickstart (recommended)

Use Copilot Chat command directly:

- `/sample-setup-cu`

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

The `/sample-setup-cu` skill sets up and verifies this flow.

## Local endpoints

| Service | Local URL |
|---|---|
| UI | `http://localhost:5173` |
| Gateway | `http://localhost:8080` |
| Inventory MCP | `http://localhost:8001` |
| Work Orders API | `http://localhost:8002` |
| Status Dashboard | `http://localhost:8003` |

## CU demo references

| Doc | When to read it |
|---|---|
| [content-understanding/README.md](content-understanding/README.md) | End-to-end CU demo walkthrough and analyzer commands |
| [services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md](services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md) | Foundry IQ minimal vs standard ingestion setup details |
| [.github/skills/sample-setup-cu/SKILL.md](.github/skills/sample-setup-cu/SKILL.md) | Copilot skill playbook used by `/sample-setup-cu` |

## Need the original full-platform guidance?

If you need detailed guidance on Toolbox integration, hosted agents,
container app deployment, and the broader original sample scope, use the
upstream repository:

- https://github.com/dbarkol/fibey-agent

You can also refer to the forked docs kept in this repo:

| Doc | Focus |
|---|---|
| [docs/toolbox-integration.md](docs/toolbox-integration.md) | Toolbox integration details |
| [docs/architecture.md](docs/architecture.md) | Full architecture and runtime modes |
| [docs/deployment.md](docs/deployment.md) | Azure deployment details |
| [infra-agent/README.md](infra-agent/README.md) | Hosted agent infrastructure notes |

## Copilot skill command

In Copilot Chat, run:

- `/sample-setup-cu`

This is the recommended way to provision CU resources, run setup scripts, and
start the demo with explicit approval checkpoints.

## Project layout (CU-relevant)

```text
content-understanding/                                # CU demo files + analyzer tools
services/foundry-iq-docs/content-understanding/docs/  # Foundry IQ CU demo docs
scripts/setup-knowledge-base.sh                       # Creates minimal/standard CU demo KBs
src/fibey/gateway/                                    # API endpoints, feature flags, health checks
ui/src/                                               # Chat UI and CU mode selectors
```

## License

Licensed under the MIT License — see [LICENSE](LICENSE).
