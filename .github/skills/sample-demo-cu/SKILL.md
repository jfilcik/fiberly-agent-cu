---
name: "CU Agent Demo Walkthrough"
description: "Guide users through interactive Content Understanding (CU) demo scenarios in this repo: agent-side CU upload modes, custom analyzer + classifier routing, and Foundry IQ minimal vs. standard ingestion. Use when the user asks to demo CU, present CU value to others, walk through CU scenarios, or compare with/without CU behavior."
tags: ['azure', 'content-understanding', 'demo', 'agent', 'foundry-iq', 'classifier', 'analyzer']
---

# CU Agent Demo Walkthrough Skill

## 🎬 How This Skill Works (Read First)

**When invoked, follow this sequence:**

1. **Present the "Introduction" section first** so the user (and audience) sees *why* CU matters in agent scenarios before any clicks happen.
2. **Show the "Demo Menu"** and ask which demo (1, 2, 3, or all in order) the user wants to run. Recommend running them in order 1 → 2 → 3 the first time (runtime first; ingestion is the heavier setup).
3. For the selected demo, walk through its **Setup check → Key code → Manual steps → What to call out** sections.
4. **Pause for the user to perform each manual step in the UI** and confirm before moving on.
5. **Remind the user to use a fresh chat session** between demos. The LLM will otherwise reuse prior context and the "without CU" baseline will look smarter than it really is.

> **Step convention used throughout this skill** (read carefully — this is the most common failure mode). The bracketed tags below are addressed to *you, the coding agent*; render them verbatim in the chat so the presenter can scan the steps quickly:
> - **`[AGENT DOES]`** — the coding agent (you) executes this step *in this chat* and shows the output to the audience. Examples: render a table, summarize a concept, recap a result.
> - **`[YOUR ACTION]`** — the user/presenter performs this step in the **Fibey demo UI** (browser at http://localhost:5173). "Your" refers to the user reading the chat. Examples: click a sidebar toggle, click a suggested-prompt tile, type a message, upload a file. The coding agent should *describe* the action and then pause for the user to confirm before continuing.
> - **`[BOTH OBSERVE]`** — the coding agent narrates what to look for in the Fibey UI output. No action in this chat.
>
> When in doubt: anything inside a fenced quote like *"Check the KB — what is …?"* is meant to be **typed (or clicked as a suggested-prompt tile) by the user into the Fibey UI**, not echoed back at the user by the coding agent. Anything rendered as a normal markdown table or paragraph in a step labeled `[AGENT DOES]` is meant to be **shown directly in this chat reply**.
>
> When a step asks the user to send a prompt that matches one of the suggestion tiles on the Fibey welcome screen, tell them they can either **click the matching tile** or **type the prompt manually** — both produce the same input.

> **Prerequisite:** the `/sample-setup` skill must have been run successfully (CU analyzers created; for Demo 3 specifically, both Foundry IQ KBs ingested; gateway + UI running). If anything is missing, route the user there first.

---

## 🎯 Introduction — Why CU in Agent Scenarios

Most agent demos fall apart on real-world documents:

- The LLM can read text but not `.docx`, scanned forms, or phone-camera photos of paper.
- Plain "convert PDF to markdown" loses table structure, so KB-grounded answers hallucinate or shift columns.
- A single prompt cannot reliably tell "is this a work order or a training certificate?" — so the agent calls the wrong tool.

**Azure Content Understanding (CU)** sits *between* the document and the LLM and solves three things this demo highlights:

| Problem | CU capability shown in this repo |
|---|---|
| KB retrieval garbles tables (collapsed cells, shifted columns) | Foundry IQ **standard** ingestion mode (CU-backed) preserves table structure |
| LLM cannot natively read `.docx`, scanned, or handwritten files | CU `prebuilt-layout` OCR + format support |
| LLM guesses the wrong field from an ambiguous document | **Custom analyzer** with field-level extraction rules (`cu_demo_work_order`) |
| Agent has no way to know which extraction strategy to use | **Classifier** routes per document type (`cu_demo_classify_and_analyze`) |

The demos below are ordered **runtime-first, ingestion-last**: Demo 1 and Demo 2 only need a Foundry account + chat model (fastest setup), while Demo 3 additionally requires Storage + AI Search for the knowledge base.

The repo wires these into the chat UI as toggles so an audience can flip them on/off live.

---

## 🗂️ Demo Menu

| Demo | Theme | Time | What it proves |
|---|---|---|---|
| **1 — Agent upload: None → Parse: prebuilt-layout** | CU at *runtime* upload time | ~3 min | LLM cannot read `.docx` at all without CU; `prebuilt-layout` unblocks the format |
| **2 — Custom Analyzer + Classifier deep dive** | *Why* CU works | ~5 min | Field-level prompts + classifier routing are what beat plain "PDF → markdown" |
| **3 — Foundry IQ Ingestion: minimal vs. standard** | CU at *ingestion* time | ~3 min | CU preserves table structure so KB-backed answers stay correct |

> **Always start a new chat session between demos.** Use the "New chat" button in the UI. Otherwise the LLM remembers the correct answer from the previous turn and the "without CU" comparison is invalid.

> **Demos 1 and 2 only require `sample-setup` with the CU-only path.** Demo 3 requires the full path (CU + Foundry IQ KB).

---

## Demo 1 — Agent Upload: None → Parse: prebuilt-layout

### Background — Agent Framework and context providers
**Microsoft Agent Framework** is the open-source Python/.NET SDK this repo uses to build the Fibey agent. It wires up the LLM, the tool calls (Inventory MCP, Work Orders API, Foundry IQ), and the message loop — so the agent code stays small and focused on prompts and tools instead of plumbing.

One of the framework's extension points is the **context provider**: a pluggable component that runs *before* each LLM call and can inject extra context (text, structured data, retrieved snippets) into the conversation. Context providers see the user's message and any attachments, decide what to do with them, and append the result so the LLM sees a richer prompt.

The **CU context provider** (`ContentUnderstandingContextProvider`) is exactly that: when the user attaches a file, it intercepts the attachment, sends it to Azure Content Understanding for analysis (using whichever analyzer the current CU Mode selects), and injects the structured result into the conversation as text the LLM can read. With this provider active, the LLM never sees the raw `.docx` or photo — it sees clean, normalized, optionally schema-validated content. With the provider disabled (CU Mode = None), attachments fall through to OpenAI's native file API, which rejects formats like `.docx`.

### What CU is solving here
Real field documents arrive as `.docx`, scanned PDFs, or phone photos. Plain LLM file upload either rejects them outright or reads them shallowly and confidently picks the wrong field. CU at upload time normalizes the format and (with a custom analyzer) extracts fields with explicit rules.

### Setup check
- `AZURE_CONTENTUNDERSTANDING_ENDPOINT` is set in `.env` (the "+" attach button appears in the chat input and the **CU Mode** selector is active in the sidebar).
- Both analyzers exist: `cu_demo_work_order` and `cu_demo_classify_and_analyze`. Recreate via the commands in [content-understanding/README.md](content-understanding/README.md) if missing.

### Key code pieces

- [src/fibey/agent/agent.py](src/fibey/agent/agent.py) — the `_CU_ANALYZER_IDS` mapping decides which analyzer the agent uses per `cu_mode`:
  - `"basic"` → `prebuilt-layout`
  - `"work_order"` → `cu_demo_classify_and_analyze`
- `create_agent(cu_mode=...)` registers a `ContentUnderstandingContextProvider` (wrapped by `_LoggingCUWrapper`) only when `cu_mode != "none"`. When `cu_mode == "none"`, attachments are sent as raw OpenAI file inputs — which fails on `.docx`.
- [src/fibey/gateway/api_server.py](src/fibey/gateway/api_server.py) — reads `cu_mode` from `POST /api/chat` body and forwards it into `_run_local(...)`.

### Manual demo steps

> **Start a new chat session before each step below.** Do not reuse the chat after a wrong answer is given — the LLM will remember the right answer otherwise.

The prompt for both steps below is the same. You can **click the suggested-prompt tile** labeled *"Review an attached file for work order details to prepare for creating a new work order."* on the welcome screen, or type it manually:

*"Review an attached file for work order details to prepare for creating a new work order."*

**Step 1 — "None" mode fails on `.docx`**
1. **`[YOUR ACTION]`** New chat in the Fibey UI. Set **CU Context Provider** to **None**.
2. **`[YOUR ACTION]`** Send the prompt (click the tile or type and Send).
3. **`[BOTH OBSERVE]`** The agent replies asking for an attachment and suggests `content-understanding/demo_files/work_order_for_prebuilt_layout.docx`.
4. **`[YOUR ACTION]`** Click **+** and attach `content-understanding/demo_files/work_order_for_prebuilt_layout.docx`, then click **Send** (no extra text needed).
5. **`[BOTH OBSERVE]`** Amber warning banner + error from OpenAI (the file API rejects `.docx`).

**Step 2 — "Parse: prebuilt-layout" reads the `.docx` as clean markdown**
1. **`[YOUR ACTION]`** New chat. Set **CU Context Provider** to **Parse: prebuilt-layout**.
2. **`[YOUR ACTION]`** Send the same prompt.
3. **`[BOTH OBSERVE]`** The agent asks for the same attachment.
4. **`[YOUR ACTION]`** Attach the same `.docx` file and click **Send**.
5. **`[BOTH OBSERVE]`** Agent answers with the work order details, including the correct technician **J. Martinez**. CU's `prebuilt-layout` turned the `.docx` into clean markdown the LLM could read — the same document that errored out in Step 1 now flows through end-to-end.

### What to do next
Once the `.docx` parses cleanly, you have two natural follow-ons — pick whichever fits the audience:
- **Ask the agent to create the work order.** In the same chat, send something like *"Yes, go ahead and create it."* The agent will call the Work Orders API with the extracted fields and confirm the new ID — closing the loop from document → structured data → real action.
- **Move on to Demo 2** to see what happens when `prebuilt-layout` alone is *not* enough — a more adversarial PDF (`work_order_for_custom_analyzer.pdf`) where **Parse: prebuilt-layout** picks the supervisor's name and only the **Classify & Analyze Work Order** mode (custom analyzer + classifier) recovers `J. Martinez` from the `Route → ...` dispatch log.

### What to call out
- The `.docx` failure in Step 1 is a real platform limitation, not a contrived bug. CU removes it.
- Step 2 proves CU `prebuilt-layout` alone is enough to unblock formats the LLM can't natively read — the agent now sees clean markdown instead of a rejected upload.
- This document is friendly enough that `prebuilt-layout` already produces the right answer. Demo 2 shows the adversarial case where field-level prompts and a classifier become necessary.

### Bonus variants
- Attach `work_order_scanned.png` (handwritten photo) in **Parse: prebuilt-layout** mode — CU's OCR handles it.

---
## Demo 2 — Custom Analyzer + Classifier Deep Dive

### Background — Custom analyzers and classifiers in CU
Demo 1 showed `prebuilt-layout` turning a `.docx` into clean markdown. That is enough for "read this file" but not for "extract these fields and call an API". Two CU primitives close that gap:

- **Custom analyzer** — a JSON **field schema** layered on top of `prebuilt-layout`. Each field has a name, a type (string / enum / number / array / object), a `GenerationMethod` (`EXTRACT` for verbatim, `CLASSIFY` for an enum, `GENERATE` for a model-reasoned value such as a normalized date or a free-form summary), and a **natural-language description** that tells the CU model exactly where in the document to look. CU returns typed JSON that matches the schema — the agent skips all markdown re-parsing and can pass the result straight to a downstream API (here, `WorkOrderCreate`).
- **Classifier** — a wrapper analyzer whose job is to decide *what kind of document* the file is and then dispatch to the right analyzer. Each category has its own description (the prompt the classifier reasons over) and an `analyzer_id` to route to. Routing to a custom analyzer means "extract fields"; routing to `prebuilt-layout` means "just give me clean markdown". This is what keeps the agent from force-fitting a safety certificate into a work-order shape.

In this repo the two are wired together: `cu_demo_classify_and_analyze` is the classifier, its `"work_order"` category routes to `cu_demo_work_order` (the field analyzer), and its `"other"` category routes to `prebuilt-layout`. The agent's CU Mode = **Classify & Analyze Work Order** points the context provider at this classifier.

### The trap document — `work_order_for_custom_analyzer.pdf`
This PDF is engineered to fool a naive extractor. The single fact that matters: **the assigned technician is `J. Martinez`** — but the document deliberately names three other people first:

| Where it appears in the PDF | Name | Why it's NOT the technician |
|---|---|---|
| Header field labeled "Field Technician" | **John Smith** | Looks authoritative but is wrong — John Smith is the on-site supervisor, repeated later in "Site Access & Contact" as `John Smith – Network Operations Supervisor`. |
| Dispatch Log row, `Dispatcher: …` field | **R. Singh** | The person who pushed the dispatch, not the one going on-site. |
| Field Completion Checklist, "Check in with contact" | **Marcus Tran** | A facilities contact at the building. |
| Dispatch Log row, `Route → …` field | **J. Martinez** ✅ | The actual dispatched tech. This is the field the custom analyzer is told to trust. |

Other expected values from the same PDF (all reasoned by the schema, not the LLM):

- `title` → `"Fiber Splice Restoration - Springfield Business Park"` (verbatim from the header heading)
- `status` → `"open"` (header reads "Status: OPEN" → CLASSIFY method snaps it to the enum)
- `priority` → `"critical"` (header badge reads "CRITICAL" → CLASSIFY method snaps it to the enum)
- `location` → `"742 Evergreen Terrace, Springfield, WA 99999"`
- `due_date` → `"2026-05-20T17:00:00Z"` (PDF shows `2026-05-20 17:00 PDT` → GENERATE method normalizes to ISO 8601 per the field's worked examples)
- `parts_needed` → `[{FIB-003, 2}, {FIB-012, 1}]` (typed array of objects from the Parts table)

### Setup check
- Both analyzers exist in your CU resource: `cu_demo_work_order` and `cu_demo_classify_and_analyze`.
- The trap PDF is at [content-understanding/demo_files/work_order_for_custom_analyzer.pdf](content-understanding/demo_files/work_order_for_custom_analyzer.pdf).

### Key code pieces

- [content-understanding/tools/create_work_order_analyzer.py](content-understanding/tools/create_work_order_analyzer.py) — defines `FIELD_SCHEMA`. Things to point at:
  - `method=GenerationMethod.GENERATE` for `title`, `description`, `assigned_technician`, `location`, `due_date`, `parts_needed`; `CLASSIFY` (with an `enum`) for `status` / `priority`.
  - The `assigned_technician` description is the star of the demo: it spells out *PRIMARY RULE* (the `Route → <name>` pattern), *WORKED EXAMPLE* (pipe-delimited dispatch row), *FALLBACK* (use header field only if no routing pattern exists), and explicit *NEVER RETURN* cases (dispatcher, supervisor, building contact). This is what tells CU to prefer `J. Martinez` over the misleading "Field Technician: John Smith" header.
  - The `due_date` description includes worked examples that anchor the ISO 8601 conversion (`'5/20/26 5:00pm' → '2026-05-20T17:00:00Z'`).
- [content-understanding/tools/create_classify_and_analyze.py](content-understanding/tools/create_classify_and_analyze.py) — defines two `ContentCategoryDefinition`s:
  - `"work_order"` → `analyzer_id="cu_demo_work_order"` (routes to structured field extraction). Its description lists the identifying signals (status label, priority label, dispatch entry, parts table, site + due date).
  - `"other"` → `analyzer_id="prebuilt-layout"` (general markdown fallback for certificates, invoices, brochures, manuals).
- [src/fibey/agent/agent.py](src/fibey/agent/agent.py) — `_CU_ANALYZER_IDS["work_order"]` points at the **classifier**, not the field analyzer directly. That extra hop is what makes unknown document types degrade gracefully into markdown instead of erroring or hallucinating fields.

### Manual demo steps

1. **`[YOUR ACTION]`** New chat in the Fibey UI. Set **CU Context Provider** to **Parse: prebuilt-layout**. Send the prompt (tile or type): *"Review an attached file for work order details to prepare for creating a new work order."* When the agent asks for a file, click **+**, attach `content-understanding/demo_files/work_order_for_custom_analyzer.pdf`, and click **Send**.
   **`[BOTH OBSERVE]`** The agent extracts the work order, but reports the assigned technician as **John Smith** (the header trap). Everything else looks plausible. Call this out as the failure case: *the document was successfully read, the LLM still picked the wrong name* because nothing told it that "Field Technician: John Smith" in the header is misleading. This is exactly what a field-level prompt fixes.

2. **`[YOUR ACTION]`** New chat. Set **CU Context Provider** to **Classify & Analyze Work Order**. Send the same prompt and attach the **same PDF** when the agent asks.
   **`[BOTH OBSERVE]`** The agent now reports the correct technician **J. Martinez**, plus `status=open`, `priority=critical`, `due_date=2026-05-20T17:00:00Z`, and the parts list `FIB-003 × 2, FIB-012 × 1`. Two things changed between Step 1 and Step 2: the classifier first decided the file *is* a work order, and the custom analyzer then applied field-level rules.

3. **`[AGENT DOES]`** Open [content-understanding/tools/create_work_order_analyzer.py](content-understanding/tools/create_work_order_analyzer.py) and quote the `assigned_technician` `description=(...)` block back to the user verbatim (the PRIMARY RULE / WORKED EXAMPLE / FALLBACK / NEVER RETURN sections). Then explain the mapping out loud:
   - **PRIMARY RULE** matches `Route → J. Martinez` in the Dispatch Log → CU returns `"J. Martinez"`.
   - **NEVER RETURN** excludes the `Dispatcher: R. Singh` value and the `Network Operations Supervisor` (John Smith).
   - **FALLBACK** is *not* triggered because the primary rule matched — that is why the header "Field Technician: John Smith" is ignored.
   Also call out `status` / `priority` as `method=CLASSIFY` with `enum=[...]` (forces the model to snap "OPEN" → `"open"`, "CRITICAL" → `"critical"`), and `due_date` as `method=GENERATE` with the worked ISO 8601 examples (forces "2026-05-20 17:00 PDT" → `"2026-05-20T17:00:00Z"`).

4. **`[AGENT DOES]`** Open [content-understanding/tools/create_classify_and_analyze.py](content-understanding/tools/create_classify_and_analyze.py) and quote both `ContentCategoryDefinition` blocks. Explain: the *classifier's* job is only to pick a category; the `analyzer_id` field is what wires each category to the actual extraction logic. The `"other"` → `"prebuilt-layout"` mapping is what makes the system safe on unexpected inputs — a safety certificate gets clean markdown instead of bogus work-order fields.

5. **`[YOUR ACTION]`** Prove the classifier fallback works from inside the UI. In the same **Classify & Analyze Work Order** chat (or a new one in the same mode), send: *"Review an attached file for work order details."* When the agent asks for a file, click **+**, attach `content-understanding/demo_files/safety_cert_splicing.pdf`, and click **Send**.
   **`[BOTH OBSERVE]`** The agent reports the file is a **training certificate, NOT a work order**, and renders a Fusion Splicing Safety Certificate summary (holder, course code, score, dates, certificate ID) instead of fabricating work-order fields. Under the hood the classifier picked the `"other"` category and routed the file to `prebuilt-layout` — the custom work-order analyzer was never invoked.

### What to call out
- The "magic" is *prompt engineering at the field level*, not a special model. Anyone reading [create_work_order_analyzer.py](content-understanding/tools/create_work_order_analyzer.py) can see exactly what the rules are and edit them in plain English.
- The trap PDF was specifically designed so the *header* is wrong and the *dispatch log* is right. That mirrors real-world systems where the latest dispatch supersedes whoever the form was originally pre-filled for.
- Custom analyzers return *typed* JSON (`status` is one of four enum values, `due_date` is ISO 8601, `parts_needed` is a `[{part_id, quantity}]` array). The agent passes this straight to `WorkOrderCreate` — no re-parsing, no shape drift.
- Classifiers make the agent's tool selection robust to wrong inputs: a safety certificate will not be force-fit into a work-order shape, it falls through to `prebuilt-layout`.

---
## Demo 3 — Foundry IQ Ingestion (Minimal vs. Standard)

### Background — Foundry IQ, Knowledge Bases, and ingestion
**Foundry IQ** is Azure AI Foundry's managed retrieval-augmented-generation (RAG) layer. Instead of each agent rolling its own vector store and chunking pipeline, Foundry IQ hosts **Knowledge Bases (KBs)** — searchable indexes built from your documents — and exposes them to agents through an MCP tool. The Fibey agent calls this MCP at runtime to ground answers in source content (procedures, OTDR reports, safety docs) rather than guessing from the LLM's training data.

A KB doesn't read the original PDF on every query; it reads a pre-processed copy. That preprocessing step is called **ingestion**: each source document is parsed, converted to text/markdown, split into chunks, embedded, and indexed. Whatever the ingestion pipeline gets wrong is baked into every future answer — there is no second chance at query time. That is why the *ingestion-time* extraction mode matters so much, and why this demo compares two KBs over the **same** source content with only the extraction mode swapped.

### What CU is solving here
At ingestion time, a basic PDF→text extractor collapses empty table cells. Numeric values in adjacent columns shift left, so the KB stores wrong data and the agent retrieves wrong data. CU-backed ingestion preserves cell boundaries as HTML, keeping sparse tables faithful.

### Setup check
- `FOUNDRY_IQ_MINIMAL_MCP_URL` and `FOUNDRY_IQ_STANDARD_MCP_URL` are set in `.env`.
- Both indexers report `status: success` (see [services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md](services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md)).
- The **Foundry IQ Ingestion** selector is visible in the Activity sidebar.

### Key code pieces

- [scripts/setup-knowledge-base.sh](scripts/setup-knowledge-base.sh) — creates two knowledge sources, one with `contentExtractionMode: minimal`, one with `contentExtractionMode: standard` (CU-backed). The mode is immutable after creation.
- [services/foundry-iq-docs/content-understanding/docs/](services/foundry-iq-docs/content-understanding/docs/) — the sparse OTDR table PDF that exercises the difference.
- Gateway wiring: [src/fibey/gateway/api_server.py](src/fibey/gateway/api_server.py) reads `foundry_iq_mode` from the request body and forwards it into `run_agent(...)`, which selects the corresponding KB MCP URL.

### Manual demo steps
1. **`[YOUR ACTION]`** Start a new chat session in the Fibey demo UI.
2. **`[YOUR ACTION]`** Open [services/foundry-iq-docs/content-understanding/docs/otdr-acceptance-results.pdf](services/foundry-iq-docs/content-understanding/docs/otdr-acceptance-results.pdf) — the source PDF that was ingested into both KBs.
3. **`[AGENT DOES]`** Render the following table preview directly in your reply (do *not* tell the user to paste it — *you* are showing the audience what CU sees). Introduce it as: "Here are the first rows of the **FIBER-BY-FIBER OTDR MEASUREMENTS** table from the PDF — note the empty `ORL @1310` cell for **F-03**":

   | Fiber ID | Route | Length (m) | Loss @1310 (dB) | Loss @1550 (dB) | ORL @1310 (dB) | ORL @1550 (dB) | Pass / Fail |
   |---|---|---|---|---|---|---|---|
   | F-01 | MPOE → IDF-1A | 312 | 0.31 | 0.22 | 48.2 | 47.8 | PASS |
   | F-02 | MPOE → IDF-1A | 312 | 0.33 | 0.24 | 47.9 | 47.5 | PASS |
   | F-03 | MPOE → IDF-1B | 448 | 0.44 | 0.31 |  | 46.1 | PASS |

   Then, still in the same reply, direct attention to row **F-03**: the `ORL @1310 (dB)` cell is **empty**, and the adjacent `ORL @1550 (dB)` cell is **46.1**. Announce the question the user is about to ask the Fibey agent: *"What is the ORL reading at 1310nm for fiber F-03?"* The correct answer is that the cell is blank / not recorded — anything that returns `46.1` has silently shifted columns.
4. **`[YOUR ACTION]`** In the Activity sidebar, set **Foundry IQ Ingestion** to **Minimal**.
5. **`[YOUR ACTION]`** Send this prompt in the Fibey UI — either **click the suggested-prompt tile** labeled *"Check the KB — what is the ORL reading at 1310nm for fiber F-03?"* on the welcome screen, or type it manually:

   *"Check the KB — what is the ORL reading at 1310nm for fiber F-03?"*
6. **`[BOTH OBSERVE]`** The answer is roughly **46.1 dB** (wrong — that value belongs to the 1550nm column; the 1310nm cell was blank and got collapsed).
7. **`[YOUR ACTION]`** Switch **Foundry IQ Ingestion** to **Standard**. The UI auto-resets the chat on mode change — this is intentional. The previous turn contained the correct answer in context, so reusing the chat would let the LLM answer from its own context instead of from the KB, invalidating the comparison. A fresh session forces retrieval to come purely from the Standard KB.
8. **`[YOUR ACTION]`** Send the **same** prompt again (click the same tile or retype it).
9. **`[BOTH OBSERVE]`** The model now reports the 1310nm ORL cell was not recorded / is blank.

### What to call out
- Same KB content, same agent, same prompt — only the ingestion mode changed.
- `minimal` is the free baseline; `standard` is what makes table-heavy KBs trustworthy.
- The setting cannot be flipped after ingestion — emphasize this is an *ingestion-time* architectural decision.
- **Peace of mind at ingestion time.** Once a KB is ingested through CU's `standard` extractor, the presenter (and the business) does not have to keep worrying about each new document type. CU's layout model is industry-leading and handles the messy reality of enterprise content in one pass:
   - **Tables with spanning cells, sparse cells, and multi-page layouts** are preserved as structured HTML — the exact problem this demo just showed.
   - **Handwritten + printed text in hundreds of languages**, plus selection marks (checkboxes), barcodes, mathematical formulas (LaTeX), embedded figures/charts with captions, and hyperlinks — all extracted with **grounding** (page + bounding-box coordinates) so downstream agents can cite source.
   - **Hierarchical sections, paragraph roles, and annotations** (strikethrough, underline, highlight) are kept, so RAG retrieval gets semantic chunks instead of a flat blob.
   - **Confidence scores** on every extraction enable human-in-the-loop review without re-OCRing the file.
- Translation for the audience: *"We ingested once, and the KB is now resilient to whatever weird PDF marketing throws at us next quarter — sparse tables, scanned forms, multilingual contracts, the lot."*

### More info before moving on
- [Azure CU document overview — Key benefits & content extraction](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/document/overview#content-extraction) (the source for the bullets above)
- [Retrieval-augmented generation with CU](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/concepts/retrieval-augmented-generation) — why `standard` ingestion is the recommended pattern for any KB-backed agent
- [Analyzer templates](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/concepts/analyzer-templates) — prebuilt starting points you do **not** have to write from scratch (this is the lead-in to Demos B and C)
- [Content Understanding Studio](https://aka.ms/cu-studio) — the no-code UI to try this on the audience's own document, live

---

## 🧰 Troubleshooting (quick)

| Symptom | Likely cause | Fix |
|---|---|---|
| CU Mode selector missing | `AZURE_CONTENTUNDERSTANDING_ENDPOINT` unset | Re-run `/sample-setup` |
| Foundry IQ Ingestion selector missing | Minimal or Standard MCP URL unset | Re-run `./scripts/setup-knowledge-base.sh --cu-demo` and set the URLs |
| "Classify & Analyze" returns null fields | `cu_demo_classify_and_analyze` analyzer missing | Re-run the two `content-understanding/tools/create_*.py` scripts |
| Standard KB answer matches Minimal | Indexer not finished | Check indexer status (`fibey-iq-standard-ks-indexer`) until `itemsProcessed > 0` |
| LLM gives correct answer in "None" mode | Chat session was reused — context leaked | **Start a new chat** and retry |

---

## 📚 References used during this demo

- [README.md](README.md) — fork scope and CU runtime expectations
- [content-understanding/README.md](content-understanding/README.md) — full document upload walkthrough
- [services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md](services/foundry-iq-docs/content-understanding/FOUNDRY_IQ_SETUP.md) — minimal vs. standard KB setup
- [.github/skills/sample-setup/SKILL.md](.github/skills/sample-setup/SKILL.md) — prerequisite setup skill
