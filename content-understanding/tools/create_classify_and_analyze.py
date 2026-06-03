"""
Create (or recreate) the 'cu_demo_classify_and_analyze' classifier analyzer.

This is Step 2 of the Fibey CU demo setup. It DEPENDS on the work order analyzer
created by create_work_order_analyzer.py (Step 1). If that analyzer does not exist,
this script will exit with a clear error and ask you to run Step 1 first.

## What it does

The classifier categorizes an uploaded document as either:
  - work_order  → routes to 'cu_demo_work_order' for structured field extraction
  - other       → falls back to 'prebuilt-layout' for general document/markdown extraction

This enables the demo progression:
  Mode "Basic CU"                → always uses prebuilt-layout (no classification)
  Mode "Classify & Analyze WO"   → uses this classifier to route intelligently

## Usage

  # Step 1 — create the work order field analyzer (prerequisite):
  uv run python content-understanding/tools/create_work_order_analyzer.py

  # Step 2 — create this classifier (depends on Step 1):
  uv run python content-understanding/tools/create_classify_and_analyze.py

  # Analyze a file with the classifier (skip create, use existing):
  uv run python content-understanding/tools/create_classify_and_analyze.py \\
      --analyze-only content-understanding/demo_files/work_order_fiber_splice.pdf

  # Create classifier AND analyze a file:
  uv run python content-understanding/tools/create_classify_and_analyze.py \\
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
from azure.identity import AzureCliCredential
from azure.ai.contentunderstanding import ContentUnderstandingClient
from azure.ai.contentunderstanding.models import (
    ContentAnalyzer,
    ContentAnalyzerConfig,
    ContentCategoryDefinition,
)
from azure.core.exceptions import HttpResponseError

CLASSIFIER_ID = "cu_demo_classify_and_analyze"
WORK_ORDER_ANALYZER_ID = "cu_demo_work_order"


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
    return ContentUnderstandingClient(endpoint=endpoint, credential=AzureCliCredential())


def check_work_order_analyzer(client: ContentUnderstandingClient) -> None:
    """Verify the prerequisite work order analyzer exists. Exit with guidance if not."""
    try:
        client.get_analyzer(analyzer_id=WORK_ORDER_ANALYZER_ID)
        print(f"  Prerequisite '{WORK_ORDER_ANALYZER_ID}' found ✓")
    except HttpResponseError as e:
        if e.status_code == 404:
            print(
                f"ERROR: Prerequisite analyzer '{WORK_ORDER_ANALYZER_ID}' not found.\n\n"
                "  This classifier routes work order documents to the work order field analyzer,\n"
                "  which must be created first.\n\n"
                "  Please run Step 1 first:\n\n"
                "    uv run python content-understanding/tools/create_work_order_analyzer.py\n\n"
                "  Then re-run this script.",
                file=sys.stderr,
            )
            sys.exit(1)
        else:
            print(
                f"ERROR: Could not verify prerequisite analyzer '{WORK_ORDER_ANALYZER_ID}'.\n"
                f"  Status: {e.status_code}\n  Message: {e.message}",
                file=sys.stderr,
            )
            sys.exit(1)


def delete_if_exists(client: ContentUnderstandingClient) -> None:
    try:
        client.get_analyzer(analyzer_id=CLASSIFIER_ID)
        print(f"  Existing classifier '{CLASSIFIER_ID}' found — deleting...")
        client.delete_analyzer(analyzer_id=CLASSIFIER_ID)
        print(f"  Deleted '{CLASSIFIER_ID}'.")
    except HttpResponseError as e:
        if e.status_code == 404:
            pass  # Does not exist, nothing to delete
        else:
            print(
                f"ERROR: Failed to check/delete classifier '{CLASSIFIER_ID}'.\n"
                f"  Status: {e.status_code}\n  Message: {e.message}",
                file=sys.stderr,
            )
            sys.exit(1)


def create_classifier(client: ContentUnderstandingClient) -> None:
    print(f"Creating classifier '{CLASSIFIER_ID}'...")

    categories = {
        "work_order": ContentCategoryDefinition(
            description=(
                "A field operations work order document issued to a technician for a specific job. "
                "Contains a job title, assigned technician name in a sign-off table, job site address, "
                "due date, parts list with part IDs (e.g. FIB-XXX), status (open/in_progress), "
                "and priority (critical/high/medium/low). Typically 1-2 pages with a professional "
                "header, checklist, and signature block."
            ),
            analyzer_id=WORK_ORDER_ANALYZER_ID,  # Route to structured field extractor
        ),
        "other": ContentCategoryDefinition(
            description=(
                "Any document that is NOT a field operations work order. This includes training "
                "certificates, inspection reports, invoices, packing slips, incident reports, "
                "safety manuals, NOC tickets, or any general business document."
            ),
            analyzer_id="prebuilt-layout",  # Fall back to general markdown extraction
        ),
    }

    config = ContentAnalyzerConfig(
        enable_segment=False,  # Each file is one document — no multi-doc segmentation needed
        content_categories=categories,
    )

    analyzer = ContentAnalyzer(
        base_analyzer_id="prebuilt-document",
        description=(
            "Fibey demo classifier: routes fiber ops work orders to the work order field extractor "
            "and all other document types to prebuilt-layout for general extraction."
        ),
        config=config,
        models={
            "completion": "gpt-4.1",
            "embedding": "text-embedding-3-large",
        },
    )

    try:
        poller = client.begin_create_analyzer(
            analyzer_id=CLASSIFIER_ID,
            resource=analyzer,
        )
        poller.result()
        print(f"  Classifier '{CLASSIFIER_ID}' created successfully.")
    except HttpResponseError as e:
        print(
            f"ERROR: Failed to create classifier.\n"
            f"  Status: {e.status_code}\n  Message: {e.message}",
            file=sys.stderr,
        )
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


def analyze_file(client: ContentUnderstandingClient, file_path: Path) -> None:
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
        print(
            f"ERROR: Unsupported file type '{suffix}'. Supported: {list(mime_map.keys())}",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"\nAnalyzing '{file_path.name}' with classifier '{CLASSIFIER_ID}'...")
    try:
        binary_data = file_path.read_bytes()
        poller = client.begin_analyze_binary(
            analyzer_id=CLASSIFIER_ID,
            binary_input=binary_data,
            content_type=content_type,
        )
        result = poller.result()
    except HttpResponseError as e:
        print(
            f"ERROR: Analysis failed.\n  Status: {e.status_code}\n  Message: {e.message}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Display classification result and any extracted fields
    if not result.contents:
        print("No content returned from classifier.")
        return

    for content in result.contents:
        # Category from classification
        category = getattr(content, "category", None)
        segments = getattr(content, "segments", None)

        if segments:
            for seg in segments:
                seg_category = getattr(seg, "category", None) or category or "(unknown)"
                print(f"\nClassified as: {seg_category}")

                # Fields (present when routed to a field extractor like cu_demo_work_order)
                fields = getattr(seg, "fields", None)
                if fields:
                    extracted = {name: extract_field_value(f) for name, f in fields.items()}
                    print("Extracted fields:")
                    print(json.dumps(extracted, indent=2, default=str))
                else:
                    # Markdown from prebuilt-layout routing
                    markdown = getattr(seg, "markdown", None)
                    if markdown:
                        preview = markdown[:500].strip()
                        print(f"Markdown preview (first 500 chars):\n{preview}")
                        if len(markdown) > 500:
                            print(f"  ... ({len(markdown)} chars total)")
        else:
            # No segments — single-document classification
            category = getattr(content, "category", None) or "(unknown)"
            print(f"\nClassified as: {category}")

            fields = getattr(content, "fields", None)
            if fields:
                extracted = {name: extract_field_value(f) for name, f in fields.items()}
                print("Extracted fields:")
                print(json.dumps(extracted, indent=2, default=str))
            else:
                markdown = getattr(content, "markdown", None)
                if markdown:
                    preview = markdown[:500].strip()
                    print(f"Markdown preview (first 500 chars):\n{preview}")
                    if len(markdown) > 500:
                        print(f"  ... ({len(markdown)} chars total)")


def main():
    parser = argparse.ArgumentParser(
        description=(
            f"Create the '{CLASSIFIER_ID}' classifier (Step 2).\n\n"
            "PREREQUISITE: Run create_work_order_analyzer.py first (Step 1)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--analyze", metavar="FILE",
        help="File to analyze after creating the classifier.",
    )
    parser.add_argument(
        "--analyze-only", metavar="FILE",
        help="Analyze a file with the existing classifier (skip create).",
    )
    args = parser.parse_args()

    client = get_client()

    if not args.analyze_only:
        print("Checking prerequisites...")
        check_work_order_analyzer(client)
        delete_if_exists(client)
        create_classifier(client)

    target = args.analyze or args.analyze_only
    if target:
        analyze_file(client, Path(target))


if __name__ == "__main__":
    main()
