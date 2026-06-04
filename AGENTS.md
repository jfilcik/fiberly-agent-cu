# AGENTS.md

Guidance for AI coding assistants (Copilot, Cursor, Claude Code, Aider, etc.)
working in this repository.

## What this repo is

A fork of the **Fibey field-ops** demo, narrowed to showcase **Azure Content
Understanding (CU)** in agent workflows. Runtime focus: `AGENT_MODE=local-direct`.

This fork is **not** the upstream hosted-mode demo. If a user wants the original
hosted Container Apps / Foundry-hosted-agent experience, point them back to the
upstream repo (`dbarkol/fibey-agent`).

## Entry point for users

If a user asks you to set up, demo, or troubleshoot this repo, **invoke the
matching `sample-*` skill**. Do not run setup commands yourself — the skills own
role probing, region checks, OS routing, and the role/plane reasoning that
trips up most users.

| User asks for | Invoke | Notes |
|---|---|---|
| "Set up this demo" / first-time use / `azd up` | `sample-setup` | Single entry point. Owns preflight + routing. |
| "Show me CU" / "Demo CU to my team" | `sample-demo-cu` | Requires `sample-setup` to have run. |
| "Fix this 403 / RBAC error" | `sample-setup` | Its preflight diagnoses role gaps. |

## Skill map

| Skill | User-invokable? | Purpose |
|---|---|---|
| `sample-setup` | ✅ **Start here** | Concept primer + shared preflight + routes to internal sub-skills |
| `sample-demo-cu` | ✅ | Guided 3-demo walkthrough (Runtime layout → Custom analyzer → Foundry IQ ingestion) |
| `sdk-internal-setup-cu` | ❌ Internal | CU endpoint + analyzers only. Called by `sample-setup`. |
| `sdk-internal-setup-foundry-iq` | ❌ Internal | KB ingestion (Storage + Search + Foundry connections). Called by `sample-setup`. |
| `sample-internal-*` | ⚠ Maintainers | Repo internals (toolbox, UI designer, etc.) |

If a user invokes an `sdk-internal-*` skill directly, redirect them to
`sample-setup` and stop — the internal skills assume preflight already ran.

## Hard rules for the agent

1. **Always run `sample-setup` preflight before touching Azure.** It is the
   single source of truth for OS, subscription, Foundry endpoint, and the
   user's role classification (Admin / Dev / Mixed / None).
2. **Never run `azd up` directly.** Let the skill decide. CU-only path uses
   `infra/cu-only/`; full path uses `infra/main.bicep`.
3. **Never run `az role assignment create` directly.** If a role is missing,
   print the exact command for the admin to run and stop.
4. **On Windows, use only built-in PowerShell.** Do not suggest Git Bash or
   WSL. Each `.sh` in `scripts/` has a `.ps1` sibling — use that on Windows.
5. **CU resource in a different region than the RG is NOT an error.** Pass
   through with an informational note. CU is region-limited; this is normal.
6. **Prefer data-plane auth (`--auth-mode login`, Bearer tokens) over keys.**
   `Contributor` is not a super user — it is a *resource manager*, not an
   *authorized resource user*. See "Roles in plain language" below.

## Roles in plain language (the most common source of pain)

Two distinct planes. Confusing them is the #1 cause of 403 in this repo.

- **Management plane** = the building. Build, renovate, hand out keys.
- **Data plane** = the rooms. Walk in, use the stuff.

| Role | Metaphor | Real meaning |
|---|---|---|
| `Owner` | Landlord | Manager + locksmith |
| `Contributor` | Building manager | Can renovate + grab master keys (`listKeys`), but **cannot change the key system** and is **not a tenant** |
| `User Access Administrator` | Locksmith | Can change who holds which key; cannot use any room |
| `Cognitive Services User` | Tenant of the AI building | Can call CU + OpenAI data plane with their own identity |
| `Azure AI User` | Tenant of a specific Foundry project apartment | Can use connections / agents / models in that project |
| `Storage Blob Data Contributor` | Tenant of the warehouse | Can read/write blobs with their own identity (no `listKeys` needed) |
| `Search Index Data Contributor` | Tenant of the library | Can CRUD indexes / KS / KB with their own identity |

**Vendor / dev workflow target**: a developer should be able to run the demo
with only data-plane (tenant) roles, no management-plane keys. The
`sample-setup` skill enforces this split.

## Where to learn more

- `README.md` — fork scope and CU runtime expectations
- `.github/skills/sample-setup/SKILL.md` — the entry-point skill
- `.github/skills/sample-demo-cu/SKILL.md` — the demo walkthrough
- `services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md` — KB internals
