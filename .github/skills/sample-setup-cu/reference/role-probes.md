# Role Probes — Batched, Scoped to Chosen Path

Used in Stage 5.2 of `sample-setup-cu`.

## Identity baseline (run once)

```bash
OID=$(az ad signed-in-user show --query id -o tsv)
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
SUB=$(az account show --query id -o tsv)
az role assignment list --assignee $OID --all \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

## Probe set (scoped to `path`)

Run all relevant probes in one batch — **do NOT stop at the first
failure**. For each, record `ok: true|false` plus the role + scope
needed. This way the Admin Request Block lists every missing role in
one shot.

| Probe | Path 1+2 | Path 3 | Path all | If fails, needs |
|---|:---:|:---:|:---:|---|
| Reader on RG | ✅ | ✅ | ✅ | `Reader` on RG *(recommended; convenience-only — covers discovery and lets `az ... show` work for sibling resources without per-resource Reader)* |
| Foundry account read (`az cognitiveservices account show -n <foundry> -g <rg>`) | ✅ | ✅ | ✅ | `Reader` on Foundry account (already implied by `Cognitive Services User`, so this rarely fails on its own) |
| CU data plane (`curl -H "Authorization: Bearer $(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)" "<cuEndpoint>contentunderstanding/analyzers?api-version=2024-12-01-preview"`) | ✅ | ⏭ | ✅ | `Cognitive Services User` on **CU account** (`cuAccountName` — may differ from `foundryAccountName`) |
| Foundry project data plane (`az rest --method get --uri "https://management.azure.com<projectId>/connections?api-version=2025-10-01-preview"`) | ✅ | ✅ | ✅ | `Azure AI User` on Foundry project |
| Storage data plane (`az storage container list --account-name <storage> --auth-mode login -o tsv`) | ⏭ | ✅ | ✅ | `Storage Blob Data Contributor` on storage |
| Search data plane (`curl -H "Authorization: Bearer $(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)" "https://<search>.search.windows.net/servicestats?api-version=2024-07-01"`) | ⏭ | ✅ | ✅ | `Search Index Data Contributor` on Search |

## Render the result table

Show ⏭ for probes skipped due to path. Example for `path=1+2 only`:

```
Path: 1+2 only

Probe                          Result   Needed if missing
-----                          ------   -----------------
Reader on RG                   ✅
Foundry account read           ✅
CU data plane                  ❌       Cognitive Services User on Foundry account
Foundry project data plane     ❌       Azure AI User on Foundry project
Storage data plane             ⏭        Not needed for this path
Search data plane              ⏭        Not needed for this path
```

## Classification

Based on probe results (only consider probes that ran):

- **`admin`** — has `Contributor` / `Owner` / `User Access Administrator`
  at subscription OR RG scope. Can run `azd up` and assign roles. (Even
  if data-plane probes fail — admin can self-assign.)
- **`dev`** — all probes required by the chosen path passed. Skip
  `azd up`, skip role assignment.
- **`mixed`** — both. Default to admin with an "act as dev" off-ramp.
- **`none`** — at least one required probe failed AND user is not
  admin → emit the Admin Request Block (`reference/admin-request-block.md`)
  with only the roles for the chosen path, then stop.

Confirm with the user before continuing:
> "Based on these probes for the **`<path>`** path, I've classified you
> as **`<track>`**." Continue as `<track>`? Options: `Yes, continue` /
> `Switch to dev track` (mixed only) / `Switch path` / `Stop here`.
