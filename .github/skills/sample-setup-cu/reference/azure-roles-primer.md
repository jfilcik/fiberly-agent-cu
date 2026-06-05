# Azure Roles Primer — Plain Language

Render this verbatim when the user reaches Stage 2 of `sample-setup-cu`.
Most users find this clarifying — it's the #1 cause of confusion in this
demo, so don't skip or summarize.

---

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

---

After rendering, ask: "Ready to start preflight? (yes / explain more)"

If "explain more": dive deeper into any role they ask about, then re-ask.
