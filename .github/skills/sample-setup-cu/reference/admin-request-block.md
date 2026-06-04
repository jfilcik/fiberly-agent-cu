# Admin Request Block — Template (emit verbatim)

Use this block whenever a developer is blocked by missing roles. Emit it
**once with every missing role bundled in**, never one role at a time.
This block is the *only* sanctioned way the orchestrator and any sub-
module ask the developer to escalate to an admin.

## Before emitting, collect

- `subscriptionId` and `subscriptionName` (from `az account show`)
- `resourceGroup`, `foundryAccountName`, `foundryProjectName`
- `cuAccountName`, `cuResourceGroup` (may equal Foundry account; may differ)
- `searchServiceName`, `storageAccountName` (Demo 3 only; omit lines if N/A)
- Developer's `oid` and `upn` (from `az ad signed-in-user show`)
- The list of failed probes from Stage 5.2 (mapping to roles)

## Template

Render exactly this, filling placeholders with collected values and
including only the role-assignment commands that correspond to actually-
failed probes (don't ask the admin to grant roles the developer already has):

```
📋 Admin help needed — please forward to your Azure subscription owner

Subscription:    <subscriptionName> (<subscriptionId>)
Resource group:  <resourceGroup>
Foundry account: <foundryAccountName>
Foundry project: <foundryProjectName>
CU account:      <cuAccountName>         # may differ from Foundry account (CU region constraints)
Search service:  <searchServiceName>     # Demo 3 only — omit if N/A
Storage account: <storageAccountName>    # Demo 3 only — omit if N/A

Developer identity to grant access to:
  UPN:       <upn>
  Object ID: <oid>

Missing access (run these in order, then tell the developer to re-login
and re-run /sample-setup-cu after ~5 minutes for role propagation):

# --- Reader on RG (only if "Reader on RG" probe failed; recommended for discovery convenience) ---
az role assignment create --assignee-object-id <oid> --assignee-principal-type User \
  --role "Reader" \
  --scope /subscriptions/<subscriptionId>/resourceGroups/<resourceGroup>

# --- CU + LLM data plane (only if "CU data plane" probe failed) ---
# Scope is the CU account, which may be a different AIServices account
# from the Foundry agent account (if the Foundry region doesn't support CU).
# Use `cuAccountName` (and its RG) here, not `foundryAccountName`.
az role assignment create --assignee-object-id <oid> --assignee-principal-type User \
  --role "Cognitive Services User" \
  --scope /subscriptions/<subscriptionId>/resourceGroups/<cuResourceGroup>/providers/Microsoft.CognitiveServices/accounts/<cuAccountName>

# --- Foundry project data plane (only if "Foundry project data plane" probe failed) ---
az role assignment create --assignee-object-id <oid> --assignee-principal-type User \
  --role "Azure AI User" \
  --scope /subscriptions/<subscriptionId>/resourceGroups/<resourceGroup>/providers/Microsoft.CognitiveServices/accounts/<foundryAccountName>/projects/<foundryProjectName>

# --- Storage data plane (Demo 3 only, if probe failed) ---
az role assignment create --assignee-object-id <oid> --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<subscriptionId>/resourceGroups/<resourceGroup>/providers/Microsoft.Storage/storageAccounts/<storageAccountName>

# --- Search data plane (Demo 3 only, if probe failed) ---
az role assignment create --assignee-object-id <oid> --assignee-principal-type User \
  --role "Search Index Data Contributor" \
  --scope /subscriptions/<subscriptionId>/resourceGroups/<resourceGroup>/providers/Microsoft.Search/searchServices/<searchServiceName>

# --- One-time Foundry MI access for KB (Demo 3 only) ---
# Required for Foundry IQ KB queries from the agent to succeed.
# Run this from a machine with az CLI as a user who has User Access Administrator on the Search service:
./scripts/setup-knowledge-base.sh --admin-prep

After all commands complete and ~5 minutes have passed for RBAC
propagation, the developer can run:
    az logout && az login
    /sample-setup-cu
and continue without further admin involvement.

Why these roles (in plain language):
- "Cognitive Services User" and "Azure AI User" are *tenant* roles — they
  let the developer call CU + Foundry from their own identity, without
  needing keys.
- "Contributor" alone is NOT enough — it manages the resource but is not
  a tenant of the data plane (this is the #1 source of 403s).
```

## When emitted from a module (mid-execution 403)

Prepend a one-sentence context before the block:

> "Hit a 403 on `<which probe / which action>`. Stopping. Please send the
> following to your admin:"
