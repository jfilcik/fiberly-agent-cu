# Content Understanding Demo

This directory contains demo files and Azure Content Understanding (CU) tooling
for the Fibey Field Ops BUILD demo.

## Demo Files

| File | Purpose |
|---|---|
| `demo_files/work_order_fiber_splice.pdf` | Professional 2-page work order — primary demo document |
| `demo_files/work_order_fiber_splice.docx` | Same work order in Word format — shows CU handles docx, OpenAI cannot |
| `demo_files/work_order_scanned.png` | Handwritten / photo-captured work order — shows advanced OCR |
| `demo_files/safety_cert_splicing.pdf` | Training certification (non-work-order) — shows classification routing |
| `demo_files/work_order_fiber_splice.json` | Expected CU extraction for the PDF and docx |
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
    --analyze content-understanding/demo_files/work_order_fiber_splice.pdf
```

Creates `cu_demo_work_order`: extracts structured fields from work order documents
(title, description, status, priority, assigned_technician, location, due_date,
parts_needed) aligned to the Fibey Work Orders API schema.

**Options:**
```bash
# Create and immediately test against the demo PDF:
uv run python content-understanding/tools/create_work_order_analyzer.py \
    --analyze content-understanding/demo_files/work_order_fiber_splice.pdf

# Test against an existing analyzer without recreating:
uv run python content-understanding/tools/create_work_order_analyzer.py \
    --analyze-only content-understanding/demo_files/work_order_scanned.png
```

### Step 2 — Classify & Analyze Classifier

> **Requires Step 1 to be completed first.**

```bash
uv run python content-understanding/tools/create_classify_and_analyze.py \
    --analyze content-understanding/demo_files/work_order_fiber_splice.pdf
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
    --analyze content-understanding/demo_files/work_order_fiber_splice.pdf

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

1. Click "+" and attach `work_order_fiber_splice.docx`.
2. Type any message (e.g. *"Extract the work order details"*) and send.

**Expected result:** An amber warning banner appears, followed by a confused or
error response from OpenAI. OpenAI's vision/file API does not support the `.docx`
format and rejects it with an HTTP 400 error. This is surfaced in the UI as a
clear warning so the limitation is obvious to the audience.

---

### Step 2 — Basic CU Reads the .docx (But Gets the Technician Wrong)

**Mode: Basic CU**

1. Keep the same `work_order_fiber_splice.docx` attachment (or reattach it).
2. Send the same prompt.

**Expected result:** The document is successfully extracted and the agent can
discuss the work order. However, it returns **Marcus Tran** as the assigned
technician — which is **wrong**. The correct technician is **J. Martinez**.

**Why does this happen?**
The document is deliberately designed to mislead a plain LLM. The document header
prominently shows:

```
Assigned Field Technician:  John Smith
```

The label explicitly says "Assigned Field Technician" — but it points to the wrong person
(John Smith is the Network Operations Supervisor listed as the site contact). With Basic CU,
the document is converted to flat markdown and the LLM reads this label at face value,
confidently returning **John Smith**.

The actual assigned technician (J. Martinez) appears only in the **Dispatch Log** row,
formatted as an internal routing audit entry:

```
Dispatch Log | 2026-05-18 08:15 PDT  |  NOC Ref: WO-DISP-0518  |  Dispatcher: R. Singh  |  Route → J. Martinez  |  Status: Pending Accept
```

Without specific instructions, the LLM doesn't know that the `Route →` value in a dispatch
log is the true technician assignment — especially when an explicit "Assigned Field Technician"
label already points elsewhere.

---

### Step 3 — Classify & Analyze Gets It Right

**Mode: Classify & Analyze Work Order**

1. Attach `work_order_fiber_splice.docx` (or the equivalent PDF — both contain
   identical content and the same deliberate ambiguity).
2. Send the same prompt.

**Expected result:** The agent now returns **J. Martinez** as the assigned
technician — **correct**. The document is also classified as `work_order`
(not `other`), and all structured fields (status, priority, due date, parts
needed, location) are extracted accurately.

**Why does this work?**
The custom `cu_demo_work_order` analyzer is configured with explicit field
descriptions that tell CU exactly where to find each field. The
`assigned_technician` description reads:

> *"Look in the 'Dispatch Information' row — it contains 'Assigned Tech:
> \<name\>'. Do NOT use 'Field Technical Contact' — that is the on-site
> building contact, not the technician."*

This field-level precision is what distinguishes a custom CU analyzer from
Basic CU + LLM guessing.

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
