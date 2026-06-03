# Content Understanding Demo

This directory contains demo files and Azure Content Understanding (CU) tooling
for the Fibey Field Ops BUILD demo.

## Demo Files

| File | Purpose |
|---|---|
| `demo_files/work_order_for_prebuilt_layout.docx` | **Primary demo** — Word work order (Aerial Drop, Cedar Grove / J. Martinez). Different content from the PDF so the Basic CU vs. classifier comparison stays clean. Shows CU enables LLMs to read `.docx` (OpenAI cannot). |
| `demo_files/work_order_for_custom_analyzer.pdf` | PDF work order with a deliberate `Dispatch Log → Route →` misdirection. Shows a custom analyzer beats Basic CU on field routing. |
| `demo_files/work_order_scanned.png` | Handwritten / photo-captured work order — shows advanced OCR |
| `demo_files/safety_cert_splicing.pdf` | Training certification (non-work-order) — shows classification routing |
| `demo_files/work_order_fiber_splice.json` | Expected CU extraction for the PDF |
| `demo_files/work_order_scanned.json` | Expected CU extraction for the PNG |

---

## Environment Setup

Add the following to your `.env` file before running the demo:

```
AZURE_CONTENTUNDERSTANDING_ENDPOINT=https://<your-foundry-resource>.services.ai.azure.com/
```

When this variable is set, the "+" file attachment button appears in the chat UI
and the CU mode selector becomes active in the sidebar.

---

## CU Analyzer Setup (Two Steps)

The demo uses two CU analyzers. Create them once before demoing.

### Step 1 — Work Order Field Analyzer

```bash
uv run python content-understanding/tools/create_work_order_analyzer.py \
    --analyze content-understanding/demo_files/work_order_for_custom_analyzer.pdf
```

Creates `cu_demo_work_order`: extracts structured fields from work order documents
(title, description, status, priority, assigned_technician, location, due_date,
parts_needed) aligned to the Fibey Work Orders API schema.

**Options:**
```bash
# Create and immediately test against the demo PDF:
uv run python content-understanding/tools/create_work_order_analyzer.py \
    --analyze content-understanding/demo_files/work_order_for_custom_analyzer.pdf

# Test against an existing analyzer without recreating:
uv run python content-understanding/tools/create_work_order_analyzer.py \
    --analyze-only content-understanding/demo_files/work_order_scanned.png
```

### Step 2 — Classify & Analyze Classifier

> **Requires Step 1 to be completed first.**

```bash
uv run python content-understanding/tools/create_classify_and_analyze.py \
    --analyze content-understanding/demo_files/work_order_for_custom_analyzer.pdf
```

Creates `cu_demo_classify_and_analyze`: classifies an uploaded document and routes it
to the appropriate analyzer.

| Classified as | Routed to | Result |
|---|---|---|
| `work_order` | `cu_demo_work_order` | Structured field extraction |
| `other` | `prebuilt-layout` | General markdown extraction |

**Options:**
```bash
# Create and test against the work order PDF:
uv run python content-understanding/tools/create_classify_and_analyze.py \
    --analyze content-understanding/demo_files/work_order_for_custom_analyzer.pdf

# Test against an existing classifier without recreating:
uv run python content-understanding/tools/create_classify_and_analyze.py \
    --analyze-only content-understanding/demo_files/safety_cert_splicing.pdf
```

---

## Demo Walkthrough

The CU mode selector lives in the Activity sidebar. Three modes are available:

| Mode | Analyzer Used |
|---|---|
| **None** | Plain OpenAI (no CU) |
| **Basic CU** | `prebuilt-layout` — converts document to markdown, no structured fields |
| **Classify & Analyze Work Order** | `cu_demo_classify_and_analyze` — classifies, then extracts structured fields |

### Step 1 — OpenAI Cannot Read a .docx

**Mode: None**

1. Click "+" and attach `work_order_for_prebuilt_layout.docx`.
2. Type any message (e.g. *"Extract the work order details"*) and send.

**Expected result:** An amber warning banner appears, followed by a confused or
error response from OpenAI. OpenAI's vision/file API does not support the `.docx`
format and rejects it with an HTTP 400 error. This is surfaced in the UI as a
clear warning so the limitation is obvious to the audience.

This is the headline point of the demo: **Word documents are everywhere in field
ops, and a plain LLM call simply can't see them.** CU bridges that gap.

---

### Step 2 — Basic CU Lets the LLM Read the .docx

**Mode: Basic CU**

1. Keep the same `work_order_for_prebuilt_layout.docx` attachment (or reattach it).
2. Send the same prompt.

**Expected result:** CU's `prebuilt-layout` analyzer converts the `.docx` into
markdown, which is then passed to the LLM. The agent can now read the document
and summarize the Cedar Grove aerial drop install, including the assigned
technician (**J. Martinez**), status, parts list, and safety protocols.

This is the "unlock" moment — the same document that the LLM rejected outright
in Step 1 is now fully readable, with no schema, no custom analyzer, just
layout extraction.

---

### Step 3 — Custom Analyzer Beats Basic CU on a Tricky PDF

**Mode: Basic CU**, then **Classify & Analyze Work Order**

Basic CU is enough to read a clean document, but real field paperwork often
bakes in routing metadata, internal codes, and ambiguous labels. The PDF demo
file is designed to surface that gap.

1. Attach `work_order_for_custom_analyzer.pdf` and send the prompt in **Basic CU** mode.
   The agent returns a confidently wrong technician — typically the on-site
   contact (e.g. **Marcus Tran**) instead of the actual assignee.
2. Switch to **Classify & Analyze Work Order** and re-send.
   The agent now returns **J. Martinez** — correct — along with structured
   status, priority, due date, parts, and location.

**Why does Basic CU get it wrong?**
The PDF prominently labels an on-site building contact as `Field Technician`. The
actual assignee appears only in the `Dispatch Log` row as internal routing
metadata:

```
Dispatch Log | 2026-05-18 08:15 PDT  |  NOC Ref: WO-DISP-0518  |  Dispatcher: R. Singh  |  Route → J. Martinez  |  Status: Pending Accept
```

Without per-field guidance, the LLM reads the prominent label at face value.

**Why does the custom analyzer get it right?**
`cu_demo_work_order` carries explicit, field-level instructions — for example,
the `assigned_technician` description tells CU that the `Route →` value in the
Dispatch Log is the true assignee, not the on-site contact. That field-level
precision is what distinguishes a custom CU analyzer from Basic CU plus an LLM
guess.

> **Known limitation (DOCX classification).** The `Classify & Analyze` route
> currently returns `other` for the `.docx` file, so it falls through to
> `prebuilt-layout` instead of the custom analyzer. Direct analysis with
> `cu_demo_work_order` against the same `.docx` extracts `J. Martinez`
> correctly, so this is a classifier-only gap (tracked as a service-side bug).
> The PDF flow is the canonical "classify & analyze" demo for now.

---

## Bonus Demos

### Bonus A — Classification Rejects a Non-Work-Order

**Mode: Classify & Analyze Work Order**

1. Attach `safety_cert_splicing.pdf` (a fiber splicing training certification).
2. Ask the agent to extract work order details.

**Expected result:** The classifier correctly identifies this as `other` (not a
work order) and routes it to the general `prebuilt-layout` extractor. The agent
explains that no work order fields were found and describes what the document
actually contains. This shows that the classifier prevents false positives —
it will not hallucinate work order fields from an unrelated document type.

---

### Bonus B — Handwritten Field Work Order via Photo Capture

**Mode: Classify & Analyze Work Order** (or **Basic CU**)

1. Attach `work_order_scanned.png` — a photo of a handwritten paper work order
   with real-world imperfections (uneven lighting, handwriting, physical form).
2. Ask the agent to extract the work order details.

**Expected result:** CU's OCR pipeline correctly reads the handwritten text and
extracts the structured fields. Standard OCR tools often struggle with
handwritten forms captured on a phone camera; Azure CU handles this natively.
This scenario reflects real field conditions where a technician photographs a
paper work order on-site.

---

## Running the Tests

```bash
uv run pytest content-understanding/tests/ -v
```

30 tests covering all three document types and both analyzers.
4 tests are marked `xfail` (known limitations: docx title/technician/location
extraction and docx classification — the custom analyzer and classifier were
trained primarily on PDF and image examples).
