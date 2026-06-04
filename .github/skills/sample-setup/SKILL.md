---
name: "Sample Setup (CU Demo Orchestrator)"
description: "User-facing entry point for setting up the CU demo fork. Explains scenarios, teaches Azure roles in plain language, runs a shared preflight, and routes to internal sub-skills. ALWAYS start here."
tags: ['azure', 'content-understanding', 'setup', 'orchestrator', 'rbac', 'preflight']
---

# sample-setup — CU Demo Orchestrator

You are the single entry point for setting up this fork. **Never run setup
commands yourself before this skill's preflight completes.** Sub-skills
(`sdk-internal-setup-cu`, `sdk-internal-setup-foundry-iq`) assume preflight
already ran and will refuse to run standalone.

## Required opening message (verbatim, before any tool call)

> 👋 **Welcome.** This setup configures the **Content Understanding (CU)
> demo fork** of Fibey. It does **not** set up the original upstream
> hosted-mode demo (Container Apps + Foundry-hosted agent). If that's what
> you want, please go back to the upstream repo (`dbarkol/fibey-agent`) and
> follow its README.
>
> I'll do four things, in order:
> 1. **Explain** the CU demo scenarios and what resources each one needs.
> 2. **Teach** Azure roles in plain language (this is where most people
>    get stuck with 403 errors).
> 3. **Preflight**: detect your OS, log-in status, subscription, Foundry
>    endpoint, and your current Azure roles.
> 4. **Route** you to the right sub-skill based on what you want to set up.
>
> Reply `continue` to start, or `not this fork` if you'd rather go back to
> upstream.

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
> Storage account and an AI Search service for the knowledge base. I'll
> ask which path you want after preflight.

## Stage 2 — Azure roles primer (plain language)

Render this verbatim. Most users find this clarifying.

> **Two planes — confusing them is the #1 cause of 403 in Azure.**
>
> - **Management plane** = *the building*. Who can build / renovate / hand
>   out keys.
> - **Data plane** = *the rooms*. Who can walk in and actually use the stuff.
>
> Common roles in this metaphor:
>
> | Role | Who they are | What they actually do |
> |---|---|---|
> | `Owner` | **Landlord** | Building manager + locksmith |
> | `Contributor` | **Building manager** | Can renovate + grab master keys (`listKeys`), but **cannot change the key system** and is **not a tenant** |
> | `User Access Administrator` | **Locksmith** | Can change who holds which key; cannot use any room |
> | `Cognitive Services User` | **Tenant** of the AI building | Can call CU + LLM data plane with their own identity |
> | `Azure AI User` | **Tenant** of a specific Foundry project apartment | Can use connections / agents / models in that project |
> | `Storage Blob Data Contributor` | **Tenant** of the warehouse | Can read/write blobs with their own identity (no `listKeys` needed) |
> | `Search Index Data Contributor` | **Tenant** of the library | Can CRUD indexes / KS / KB with their own identity |
>
> Key insight: **`Contributor` is NOT a super user.** It's a resource
> manager, not an authorized resource user. If you only have Contributor
> and you try to read a blob with your Entra identity, it will 403 —
> because Contributor doesn't include data-plane access. That's why the
> dev path of this skill uses *tenant* roles (data plane), not Contributor.

Ask: "Ready to start preflight? (yes / explain more)"

If "explain more": dive deeper into any role they ask about, then re-ask.

## Stage 3 — Preflight (read-only probes)

Run in order. Each step persists its result in skill context for sub-skills.

### 3.1 OS detection

Probe (try Bash first, fall back to PowerShell):
```bash
uname -s 2>/dev/null || echo "windows-or-unknown"
```
If output contains `Linux` → `os=linux`. `Darwin` → `os=macos`. Otherwise
ask: "Are you on Windows? (yes/no)" — assume `os=windows` on yes.

**Critical rule going forward:** if `os=windows`, emit only PowerShell
commands. Never suggest Git Bash or WSL.

### 3.2 CLI presence

```
az version
azd version
```

If `az` missing, install guidance:
- macOS: `brew install azure-cli`
- Windows (PowerShell): `winget install Microsoft.AzureCLI`
- Linux: see https://learn.microsoft.com/cli/azure/install-azure-cli

`azd` is only needed if user chose admin track later. Don't block on it now.

### 3.3 Sign-in + subscription

```
az account show -o table
```

If not signed in:
- Windows: `az login` (opens browser)
- macOS/Linux: `az login`

Confirm subscription. If multiple, ask which one to use:
`az account set --subscription <id>`

### 3.4 Ask for Foundry project endpoint

> "Paste your `FOUNDRY_PROJECT_ENDPOINT`. Format:
> `https://<account>.services.ai.azure.com/api/projects/<project>`.
> If you don't know it, I can list candidates from your subscription."

Discovery command if needed:
```
az cognitiveservices account list --query "[?kind=='AIServices'].{name:name, rg:resourceGroup, location:location, endpoint:properties.endpoint}" -o table
```

Then list projects under chosen account:
```
az resource list --resource-type Microsoft.CognitiveServices/accounts/projects --query "[?contains(id,'/accounts/<account>/projects/')].{name:name, id:id}" -o table
```

Parse endpoint into:
- `foundryAccountName`
- `foundryProjectName`
- `foundryResourceGroup` (from `az cognitiveservices account show`)

### 3.5 Confirm Foundry resource exists (read-only)

```
az cognitiveservices account show --name <foundryAccountName> --resource-group <foundryResourceGroup>
```

If 403 / 404: ask for `Reader` on the RG. Stop.

### 3.6 Region probe (informational, never blocking)

Collect regions of:
- RG: `az group show -n <rg> --query location -o tsv`
- Foundry account: from previous show
- (if user picks Demo 3 path) Storage and Search

Render table. If regions differ, print:
> ℹ️ Detected region mismatch. **This is supported and common** because CU
> is only available in select regions. Continuing — expect minor latency
> if KB Storage / Search end up in a different region from Foundry.

**Do not block. Do not ask the user to take action.**

### 3.7 Role probe (the important one)

```
OID=$(az ad signed-in-user show --query id -o tsv)
SUB=$(az account show --query id -o tsv)
az role assignment list --assignee $OID --all \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

Render the table. Then classify into a **track**:

- **`admin`** — has `Contributor` / `Owner` / `User Access Administrator`
  at subscription OR RG scope. Can run `azd up` and assign roles.
- **`dev`** — has data-plane roles only (`Cognitive Services User`,
  `Azure AI User`, etc.) on Foundry / Storage / Search. Cannot run
  `azd up`, cannot assign roles.
- **`mixed`** — both. Default to admin, with an "act as dev" off-ramp.
- **`none`** — neither. Stop, print explicit "ask your admin for X"
  block.

### 3.8 Render classification + confirm

Tell the user:
> "Based on your roles, I've classified you as **`<track>`**. Here's what
> that means:
>
> - **Admin**: I'll offer to provision resources via `azd` (or `az`) and
>   pre-assign data-plane roles. After provisioning, I'll emit a
>   handoff block you can paste to a developer who'll run the demo.
> - **Dev**: I'll skip all provisioning and role-assignment commands.
>   I'll only run data-plane operations (upload docs, create
>   analyzers, build KB). If any 403 surfaces, I'll print the exact
>   `az role assignment create` line for your admin and stop.
> - **None**: I can't proceed. Here's the exact list of roles to
>   request: [print copy-pasteable role assignments]."

Ask: "Continue as `<track>`?" Options:
- `Yes, continue`
- `Switch to dev track` (only shown for `mixed`)
- `Stop here`

## Stage 4 — Path selection

Ask:
> "Which demos do you want to set up?
> - `1+2 only` (CU runtime, fastest — invokes `sdk-internal-setup-cu`)
> - `all three` (1+2 then KB — invokes both sub-skills in order)
> - `3 only` (KB; assumes 1+2 already done — invokes `sdk-internal-setup-foundry-iq`)"

## Stage 5 — Invoke sub-skills

For each chosen sub-skill, pass the context dict:
```
{
  "os": "<linux|macos|windows>",
  "subscriptionId": "...",
  "tenantId": "...",
  "foundryAccountName": "...",
  "foundryAccountResourceId": "...",
  "foundryProjectEndpoint": "...",
  "foundryResourceGroup": "...",
  "track": "<admin|dev|mixed>",
  "roleProbe": { ... }
}
```

Invoke in this order:
- If `1+2 only` or `all three`: `sdk-internal-setup-cu` first
- If `all three` or `3 only`: `sdk-internal-setup-foundry-iq` after (or alone)

Each sub-skill reports back success + env keys written.

## Stage 6 — Final handoff

After all selected sub-skills succeed:

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

If user is on admin track, also emit a copy-paste **Dev Handoff Block** so
they can give a developer just the env vars + role assignments they need:

```
# Dev handoff — paste this into your .env (and ensure roles below are assigned)

AZURE_CONTENTUNDERSTANDING_ENDPOINT=...
FOUNDRY_PROJECT_ENDPOINT=...
FOUNDRY_MODEL=...
AZURE_AI_MODEL_DEPLOYMENT_NAME=...
FOUNDRY_IQ_MINIMAL_MCP_URL=...   # only if Demo 3 was set up
FOUNDRY_IQ_STANDARD_MCP_URL=...  # only if Demo 3 was set up

# Roles required on the dev's identity:
# - Cognitive Services User      on Foundry account
# - Azure AI User                 on Foundry project
# - Storage Blob Data Contributor on storage (Demo 3 only)
# - Search Index Data Contributor on Search service (Demo 3 only)
# - Reader                        on the resource group
```

## Hard rules

1. Never run `azd up` until after preflight + path selection + user confirm.
2. Never run `az role assignment create` directly. Print it for the admin
   instead. (Only `--admin-prep` flag in `setup-knowledge-base.sh`, run
   intentionally by an admin, assigns the Foundry MI's KB role.)
3. On Windows, **only PowerShell** — never Git Bash, never WSL.
4. Region mismatches are informational, never blocking.
5. `Contributor` is not a super user. If the user assumes it is, gently
   re-explain using the building/tenant metaphor.
6. If a user asks to set up the upstream hosted-mode demo, redirect them
   to the upstream repo and stop.
