# Fibey Field Ops

> 🤖 **Using an AI coding assistant?** See [`AGENTS.md`](AGENTS.md) for the
> entry point. TL;DR: invoke the `sample-setup-cu` skill.

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

Use the Copilot Chat command from any agent (VS Code Copilot, Cursor, Claude Code, etc.):

- **`/sample-setup-cu`** — single entry point for setup

The orchestrator skill walks you through, in order:

1. **Concept primer** — 3 CU demos, what each needs, and a plain-language Azure role guide (the landlord / building-manager / tenant metaphor that makes 403s obvious).
2. **Preflight** — OS detection (Windows PowerShell or macOS/Linux Bash, no Git Bash/WSL needed), `az login`, subscription, and Foundry endpoint discovery.
3. **Path selection** — pick `Demos 1+2 only` (fastest — Foundry account + chat model only) or `all three` (adds Storage + AI Search for the KB demo). Each option lists the exact roles it needs up front.
4. **Role probe (scoped to your path)** — auto-detects Admin / Dev / Mixed / None track. If you're a dev missing roles, it emits a single copy-pasteable **Admin Request Block** with only the roles you actually need.
5. **Configure CU + (optionally) Foundry IQ KB** — writes the needed values to `.env`, creates the CU analyzers, and (for the KB path) provisions the two knowledge bases. When it finishes you can open the UI and start running demos.

After setup, open the UI:

- http://localhost:5173

Then run the interactive demo walkthrough:

- **`/sample-demo-cu`**

This skill drives the three CU demos in order — runtime `prebuilt-layout` (`.docx` unblock), custom analyzer + classifier (adversarial PDF), and Foundry IQ minimal vs. standard ingestion (table preservation in KB) — with manual steps and talking points for each.

## Prerequisites (minimum)

- Python 3.12+
- Node.js 20+
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- Azure CLI (`az`)
- Azure Developer CLI (`azd`) — only needed if you're the admin provisioning resources (dev track skips it)
- **Windows**: PowerShell 5.1+ (ships with Windows 10/11). No Git Bash or WSL required.
- **macOS / Linux**: Bash 4+.

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

## CU demo references

| Doc | When to read it |
|---|---|
| [AGENTS.md](AGENTS.md) | **AI assistants — start here.** Skill map + hard rules + role primer. |
| [content-understanding/README.md](content-understanding/README.md) | End-to-end CU demo walkthrough and analyzer commands |
| [services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md](services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md) | Foundry IQ minimal vs standard ingestion setup details |
| [.github/skills/sample-setup-cu/SKILL.md](.github/skills/sample-setup-cu/SKILL.md) | Orchestrator skill — concept primer, preflight, role probing, routing |
| [.github/skills/sample-setup-cu/reference/](.github/skills/sample-setup-cu/reference/) | Modules loaded by the orchestrator on demand (Azure role primer, role probes, admin request block, CU + analyzers, Foundry IQ KB) |
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
