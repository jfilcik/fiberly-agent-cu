"""
Create (or recreate) the 'cu_demo_work_order' custom Content Understanding analyzer.

The analyzer uses prebuilt-layout OCR + a field schema aligned to the Fibey
Work Orders API (WorkOrderCreate model) to extract structured work order data
from PDFs and images.

Usage:
    uv run python content-understanding/tools/create_work_order_analyzer.py

    Optionally analyze a file afterwards:
    uv run python content-understanding/tools/create_work_order_analyzer.py \
        --analyze content-understanding/demo_files/work_order_fiber_splice.pdf

Environment (loaded from .env at repo root):
    AZURE_CONTENTUNDERSTANDING_ENDPOINT  — required
"""

import argparse
import json
import sys
from pathlib import Path

# Load .env from repo root (two levels up from this file)
_REPO_ROOT = Path(__file__).parent.parent.parent
_ENV_FILE = _REPO_ROOT / ".env"

from dotenv import load_dotenv
load_dotenv(_ENV_FILE)

import os
from azure.core.credentials import AzureKeyCredential
from azure.identity import AzureCliCredential
from azure.ai.contentunderstanding import ContentUnderstandingClient
from azure.ai.contentunderstanding.models import (
    ContentAnalyzer,
    ContentAnalyzerConfig,
    ContentFieldSchema,
    ContentFieldDefinition,
    ContentFieldType,
    GenerationMethod,
)
from azure.core.exceptions import HttpResponseError

ANALYZER_ID = "cu_demo_work_order"

FIELD_SCHEMA = ContentFieldSchema(
    name="work_order_schema",
    description=(
        "Schema for extracting structured work order data from field operations documents. "
        "Fields match the Fibey Work Orders API (WorkOrderCreate model)."
    ),
    fields={
        "title": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.EXTRACT,
            description="The work order title as shown in the document header.",
        ),
        "description": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.GENERATE,
            description=(
                "A full description of the job to be performed, drawn from the "
                "'Job Description' or 'Details' section of the document."
            ),
        ),
        "status": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.CLASSIFY,
            description="Current status of the work order.",
            enum=["open", "in_progress", "completed", "cancelled"],
        ),
        "priority": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.CLASSIFY,
            description="Priority level of the work order.",
            enum=["low", "medium", "high", "critical"],
        ),
        "assigned_technician": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.EXTRACT,
            description=(
                "The name of the field technician actively dispatched/routed to perform "
                "this work order on-site. This is the person currently accountable for "
                "executing the job, NOT a default contact, supervisor, or NOC representative. "
                "\n\n"
                "EXTRACTION PRIORITY (highest to lowest):\n"
                "1. HIGHEST PRIORITY: Look in any 'Dispatch Log', 'Dispatch', 'Routing', or "
                "'Assignment' section/row/entry. Find a routing arrow ('->', '→', '>>') or "
                "keyword ('Route', 'Routed to', 'Assigned to', 'Dispatched to', 'Tech:', "
                "'Assignee:') followed by a person's name. This is the assigned technician.\n"
                "2. If no dispatch log exists, look for an explicit 'Assigned Technician', "
                "'Field Tech (Assigned)', or 'On-Site Technician' field with a non-empty value.\n"
                "3. Only as a LAST RESORT (no dispatch info anywhere), use a generic "
                "'Field Technician' header field.\n"
                "\n"
                "STRICT EXCLUSIONS - never return these as assigned_technician:\n"
                "- The dispatcher (person who sent/created the dispatch, e.g. 'Dispatcher: X')\n"
                "- The on-site building/facility contact (e.g. 'Site Contact', 'Contact:', "
                "'Building Facilities', 'Facility Manager')\n"
                "- A network/operations supervisor listed in 'Site Access', 'Contact', or "
                "header metadata (e.g. 'Network Operations Supervisor')\n"
                "- Anyone with a job title indicating supervisory/management role rather than "
                "field execution\n"
                "\n"
                "TIE-BREAKER: If a name appears in BOTH a header field (like 'Field Technician') "
                "AND in a 'Site Access'/'Contact' section as a supervisor or facility contact, "
                "that name is almost certainly NOT the assigned technician. The real assigned "
                "technician will be in the dispatch/routing log.\n"
                "\n"
                "FORMAT: Return the name exactly as written (e.g. 'J. Martinez'), without "
                "titles, honorifics, or role descriptions."
            ),
        ),
        "location": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.EXTRACT,
            description="The physical job site address or location identifier.",
        ),
        "due_date": ContentFieldDefinition(
            type=ContentFieldType.STRING,
            method=GenerationMethod.GENERATE,
            description=(
                "The due date for the work order in ISO 8601 format (YYYY-MM-DDThh:mm:ssZ). "
                "Always convert the date to this format. Examples: "
                "'5/20/26 5:00pm' → '2026-05-20T17:00:00Z', "
                "'2026-05-20 17:00 PDT' → '2026-05-20T17:00:00Z', "
                "'May 20, 2026' → '2026-05-20T00:00:00Z'. "
                "If no time is given, use T00:00:00Z. Never return null for this field."
            ),
        ),
        "parts_needed": ContentFieldDefinition(
            type=ContentFieldType.ARRAY,
            method=GenerationMethod.GENERATE,
            description=(
                "List of parts and materials required. Each item has: "
                "'part_id' (string, format FIB-XXX) and 'quantity' (integer >= 1)."
            ),
            item_definition=ContentFieldDefinition(
                type=ContentFieldType.OBJECT,
                properties={
                    "part_id": ContentFieldDefinition(
                        type=ContentFieldType.STRING,
                        description="Part identifier in format FIB-XXX (e.g. FIB-003).",
                    ),
                    "quantity": ContentFieldDefinition(
                        type=ContentFieldType.NUMBER,
                        description="Number of units required, must be >= 1.",
                    ),
                },
            ),
        ),
    },
)


def get_client() -> ContentUnderstandingClient:
    endpoint = os.getenv("AZURE_CONTENTUNDERSTANDING_ENDPOINT", "").strip()
    if not endpoint:
        print(
            "ERROR: AZURE_CONTENTUNDERSTANDING_ENDPOINT is not set.\n"
            f"  Looked for .env at: {_ENV_FILE}\n"
            "  Set this variable in your .env file or environment.",
            file=sys.stderr,
        )
        sys.exit(1)

    key = os.getenv("AZURE_CONTENTUNDERSTANDING_KEY", "").strip()
    if key:
        return ContentUnderstandingClient(endpoint=endpoint, credential=AzureKeyCredential(key))

    return ContentUnderstandingClient(endpoint=endpoint, credential=AzureCliCredential())


def delete_if_exists(client: ContentUnderstandingClient) -> None:
    try:
        client.get_analyzer(analyzer_id=ANALYZER_ID)
        print(f"  Existing analyzer '{ANALYZER_ID}' found — deleting...")
        client.delete_analyzer(analyzer_id=ANALYZER_ID)
        print(f"  Deleted '{ANALYZER_ID}'.")
    except HttpResponseError as e:
        if e.status_code == 404:
            pass  # Does not exist, nothing to delete
        else:
            print(f"ERROR: Failed to check/delete analyzer: {e.message}", file=sys.stderr)
            sys.exit(1)


def create_analyzer(client: ContentUnderstandingClient) -> None:
    print(f"Creating analyzer '{ANALYZER_ID}'...")
    try:
        poller = client.begin_create_analyzer(
            analyzer_id=ANALYZER_ID,
            resource=ContentAnalyzer(
                base_analyzer_id="prebuilt-document",
                description=(
                    "Fibey field ops work order extractor. Extracts structured fields "
                    "matching the WorkOrderCreate API schema."
                ),
                config=ContentAnalyzerConfig(
                    enable_layout=True,
                    enable_ocr=True,
                ),
                field_schema=FIELD_SCHEMA,
                models={
                    "completion": "gpt-4.1",
                    "embedding": "text-embedding-3-large",
                },
            ),
        )
        poller.result()
        print(f"  Analyzer '{ANALYZER_ID}' created successfully.")
    except HttpResponseError as e:
        print(f"ERROR: Failed to create analyzer.\n  Status: {e.status_code}\n  Message: {e.message}", file=sys.stderr)
        sys.exit(1)


def extract_field_value(field) -> object:
    """Recursively extract a Python-native value from a typed ContentField."""
    from azure.ai.contentunderstanding.models import (
        StringField, NumberField, IntegerField, BooleanField,
        DateField, TimeField, ArrayField, ObjectField,
    )
    if isinstance(field, StringField):
        return field.value_string
    if isinstance(field, (NumberField, IntegerField)):
        return getattr(field, "value_number", None) or getattr(field, "value_integer", None)
    if isinstance(field, BooleanField):
        return field.value_boolean
    if isinstance(field, DateField):
        return str(field.value_date) if field.value_date else None
    if isinstance(field, TimeField):
        return str(field.value_time) if field.value_time else None
    if isinstance(field, ArrayField):
        return [extract_field_value(item) for item in (field.value_array or [])]
    if isinstance(field, ObjectField):
        return {k: extract_field_value(v) for k, v in (field.value_object or {}).items()}
    return None


def analyze_file(client: ContentUnderstandingClient, file_path: Path) -> dict:
    if not file_path.exists():
        print(f"ERROR: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    suffix = file_path.suffix.lower()
    mime_map = {
        ".pdf": "application/pdf",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".tiff": "image/tiff",
        ".bmp": "image/bmp",
    }
    content_type = mime_map.get(suffix)
    if not content_type:
        print(f"ERROR: Unsupported file type '{suffix}'. Supported: {list(mime_map.keys())}", file=sys.stderr)
        sys.exit(1)

    print(f"\nAnalyzing '{file_path.name}' with analyzer '{ANALYZER_ID}'...")
    try:
        binary_data = file_path.read_bytes()
        poller = client.begin_analyze_binary(
            analyzer_id=ANALYZER_ID,
            binary_input=binary_data,
            content_type=content_type,
        )
        result = poller.result()
    except HttpResponseError as e:
        print(f"ERROR: Analysis failed.\n  Status: {e.status_code}\n  Message: {e.message}", file=sys.stderr)
        sys.exit(1)

    fields = {}
    if result.contents:
        for content in result.contents:
            if hasattr(content, "fields") and content.fields:
                for name, field in content.fields.items():
                    fields[name] = extract_field_value(field)

    print("\nExtracted fields:")
    print(json.dumps(fields, indent=2, default=str))
    return fields


def main():
    parser = argparse.ArgumentParser(description="Create the cu_demo_work_order CU analyzer.")
    parser.add_argument("--analyze", metavar="FILE", help="File to analyze after creating the analyzer.")
    parser.add_argument("--analyze-only", metavar="FILE", help="Analyze a file with existing analyzer (skip create).")
    args = parser.parse_args()

    client = get_client()

    if not args.analyze_only:
        delete_if_exists(client)
        create_analyzer(client)

    target = args.analyze or args.analyze_only
    if target:
        analyze_file(client, Path(target))


if __name__ == "__main__":
    main()
