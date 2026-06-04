---
name: "Sample Setup (CU Demo)"
description: "User-facing entry point for setting up the CU demo fork. Explains scenarios, teaches Azure roles in plain language, runs a shared preflight, probes only the roles needed for the chosen demo path, and configures CU + (optionally) Foundry IQ KB. ALWAYS start here."
tags: ['azure', 'content-understanding', 'setup', 'orchestrator', 'rbac', 'preflight']
---

# sample-setup-cu — CU Demo Setup

You are the single entry point for setting up this fork.

**Never run setup commands yourself before this skill's preflight completes.**
Detailed steps live in `reference/*.md` — load them lazily when each stage
needs them so the model isn't carrying the whole script every turn.

## Reference files (load on demand)

- `reference/azure-roles-primer.md` — Stage 2 plain-language role guide
- `reference/role-probes.md` — Stage 5 probe table + classification
- `reference/admin-request-block.md` — Stage 8 templated ask-admin message
- `reference/cu-endpoint-and-analyzers.md` — Stage 6 module for Demos 1+2
- `reference/foundry-iq-kb.md` — Stage 6 module for Demo 3

## Required opening message (verbatim, before any tool call)

> 👋 **Welcome.** This setup configures the **Content Understanding (CU)
> demo fork** of Fibey. It does **not** set up the original upstream
> hosted-mode demo (Container Apps + Foundry-hosted agent). If that's
> what you want, please go back to the upstream repo (`dbarkol/fibey-agent`)
> and follow its README.
>
> I'll do four things, in order:
> 1. **Explain** the CU demo scenarios and what resources each one needs.
> 2. **Teach** Azure roles in plain language (this is where most people
>    get stuck with 403 errors).
> 3. **Preflight + path selection**, then **probe only the roles your
>    chosen path needs**.
> 4. **Configure** CU + (optionally) Foundry IQ KB using data-plane auth.
>
> Reply `continue` to start, or `not this fork` if you'd rather go back
> to upstream.

Wait for confirmation. If user says "not this fork", point to
`https://github.com/dbarkol/fibey-agent` and stop.

## Stage 1 — Explain CU demo scenarios

Render this table verbatim:

| Demo | What it shows | Resources you'll need |
|---|---|---|
| **Demo 1** — Runtime `prebuilt-layout` | CU lets the LLM read `.docx` / scanned files that OpenAI native upload rejects | Foundry account + project + 1 chat model |
| **Demo 2** — Custom analyzer + classifier | Field-level extraction beats plain markdown for adversarial documents | same as Demo 1 |
| **Demo 3** — Foundry IQ minimal vs standard ingestion | CU preserves table structure during KB ingestion, so retrieval-grounded answers stay correct | Demo 1 + Storage account + AI Search |

Then say:
> Demos 1 and 2 are runtime-only — fastest to set up. Demo 3 adds a
> Storage account and an AI Search service for the knowledge base.

## Stage 2 — Azure roles primer

Read `reference/azure-roles-primer.md` and follow its instructions
(render the metaphor table verbatim, ask the user if they want
clarification before continuing).

## Stage 3 — Preflight (no role probes yet)

### 3.1 OS detection
```bash
uname -s 2>/dev/null || echo "windows-or-unknown"
```
`Linux` → `os=linux`. `Darwin` → `os=macos`. Otherwise ask:
"Are you on Windows? (yes/no)" — assume `os=windows` on yes.

**Critical:** if `os=windows`, emit only PowerShell commands. Never
suggest Git Bash or WSL.

### 3.2 CLI presence
```
az version
azd version
```
If `az` missing:
- macOS: `brew install azure-cli`
- Windows: `winget install Microsoft.AzureCLI`
- Linux: https://learn.microsoft.com/cli/azure/install-azure-cli

`azd` is admin-track-only; don't block on it now.

### 3.3 Sign-in + subscription
```
az account show -o table
```
If not signed in: `az login`. Confirm subscription. Multi-sub:
`az account set --subscription <id>`.

### 3.4 Ask for Foundry project endpoint

> "Paste your `FOUNDRY_PROJECT_ENDPOINT`. Format:
> `https://<account>.services.ai.azure.com/api/projects/<project>`.
> If you don't know it, I can list candidates from your subscription."

Discovery (only if needed):
```
az cognitiveservices account list --query "[?kind=='AIServices'].{name:name, rg:resourceGroup, location:location, endpoint:properties.endpoint}" -o table
```

Parse endpoint into `foundryAccountName`, `foundryProjectName`,
`foundryResourceGroup`.

### 3.5 Confirm Foundry resource exists
```
az cognitiveservices account show --name <foundryAccountName> --resource-group <foundryResourceGroup>
```
If 403 / 404: ask for `Reader` on the RG (or directly on the Foundry
account). Stop.

## Stage 4 — Path selection (ASK BEFORE PROBING ROLES)

Picking the path first means Stage 5 only probes (and Stage 8 only asks
for) the roles the chosen demos actually need. Don't scare the user
with red ❌ on Storage/Search probes they don't use.

Ask:
> "Which demos do you want to set up?
> - `1+2 only` — CU runtime (`prebuilt-layout` + custom analyzer). Fastest.
>   **Resources**: Foundry account + project + 1 chat model.
>   **Dev roles**: `Cognitive Services User` on Foundry account,
>   `Azure AI User` on Foundry project.
> - `all three` — 1+2 then KB ingestion comparison. Adds Storage + AI Search.
>   **Adds resources**: Storage account + AI Search service.
>   **Adds dev roles**: `Storage Blob Data Contributor` on storage,
>   `Search Index Data Contributor` on Search.
> - `3 only` — KB only (assumes 1+2 already configured)."

Persist `path` in skill context.

## Stage 5 — Region + role probes (scoped to chosen path)

### 5.1 Region probe (informational, never blocking)

Collect regions of: RG, Foundry account, and (only if path includes
Demo 3) Storage and Search. Render table.

If regions differ, print once:
> ℹ️ Detected region mismatch. **This is supported and common** because
> CU is only available in select regions. Continuing — expect minor
> latency if KB Storage / Search end up in a different region from Foundry.

**Do not block.**

### 5.2 Role probes + classification

Load `reference/role-probes.md` and follow it. The probe set is filtered
by `path`. Aggregate all failures (do NOT stop at the first), then
classify into `admin` / `dev` / `mixed` / `none`.

If `none`: load `reference/admin-request-block.md`, render it with only
the roles the path needs, then stop.

Confirm the classification with the user before continuing.

## Stage 6 — Run the chosen modules

Pass this context dict forward (modules read it; don't re-probe):
```
{
  "os": "<linux|macos|windows>",
  "subscriptionId": "...", "tenantId": "...",
  "foundryAccountName": "...", "foundryAccountResourceId": "...",
  "foundryProjectEndpoint": "...", "foundryResourceGroup": "...",
  "track": "<admin|dev|mixed>",
  "roleProbe": { ... }
}
```

Module sequence (driven by `path`):
- `1+2 only` → load and follow `reference/cu-endpoint-and-analyzers.md`
- `3 only` → load and follow `reference/foundry-iq-kb.md`
- `all three` → run `cu-endpoint-and-analyzers.md` first, then
  `foundry-iq-kb.md`

If a module hits a 403 mid-execution (e.g. propagation lag): load
`reference/admin-request-block.md` and emit it with the specific
missing role appended. Modules must never improvise an ask-admin
message.

## Stage 7 — Final handoff

After all selected modules succeed:

```
✅ Setup complete.

Demos enabled:
  - Demo 1 (Runtime prebuilt-layout): ✅
  - Demo 2 (Custom analyzer + classifier): ✅
  - Demo 3 (Foundry IQ ingestion): <✅ or ⏭ skipped>

Next: invoke `sample-demo-cu` to run the guided walkthrough.

Quick validation URLs (once you start the stack):
  - UI: http://localhost:5173
  - Gateway health: http://localhost:8080/api/health
  - Gateway features: http://localhost:8080/api/features
```

If user is on **admin track**, also emit a copy-paste **Dev Handoff Block**:

```
# Dev handoff — paste this into your .env (and ensure roles below are assigned)

AZURE_CONTENTUNDERSTANDING_ENDPOINT=...
FOUNDRY_PROJECT_ENDPOINT=...
FOUNDRY_MODEL=...
AZURE_AI_MODEL_DEPLOYMENT_NAME=...
FOUNDRY_IQ_MINIMAL_MCP_URL=...   # only if Demo 3 was set up
FOUNDRY_IQ_STANDARD_MCP_URL=...  # only if Demo 3 was set up

# Roles required on the developer's identity:
# - Cognitive Services User      on Foundry account
# - Azure AI User                 on Foundry project
# - Storage Blob Data Contributor on storage (Demo 3 only)
# - Search Index Data Contributor on Search service (Demo 3 only)
# - Reader                        on the resource group (recommended; data-plane roles above already imply read access to the specific resources)
```

## Stage 8 — Admin Request Block (load on demand)

Defined in `reference/admin-request-block.md`. Render it verbatim whenever:
- Stage 5.3 classification produces `none`
- A module in Stage 6 hits a 403 mid-execution

Only include role-assignment commands for probes that **actually failed**
for the **chosen path**. Don't ask the admin to grant roles the developer
already has, or roles for a path they didn't pick.

## Hard rules

1. Never run `azd up` until after preflight + path selection + user confirm.
2. Never run `az role assignment create` directly. Render Stage 8's
   Admin Request Block instead. (Only `--admin-prep` flag in
   `setup-knowledge-base.{sh,ps1}`, run intentionally by an admin,
   assigns the Foundry MI's KB role.)
3. On Windows, **only PowerShell** — never Git Bash, never WSL.
4. Region mismatches are informational, never blocking.
5. `Contributor` is not a super user. If the user assumes it is, gently
   re-explain using the building/tenant metaphor.
6. If a user asks to set up the upstream hosted-mode demo, redirect
   them to the upstream repo and stop.
7. **Never improvise an ask-admin message.** Always emit Stage 8's
   Admin Request Block, with only the role lines that match actually-
   failed probes for the chosen path. Modules must follow this rule too.
