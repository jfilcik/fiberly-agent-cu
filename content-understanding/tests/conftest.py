"""
Shared fixtures for Content Understanding live tests.

These tests make real Azure API calls. Requires:
  - AZURE_CONTENTUNDERSTANDING_ENDPOINT in .env (repo root)
  - Azure CLI logged in (az login)
  - Both analyzers already created:
      cu_demo_work_order          (Step 1)
      cu_demo_classify_and_analyze (Step 2)

Run:
    uv run pytest content-understanding/tests/ -v
"""

import os
import sys
from pathlib import Path

import pytest
from dotenv import load_dotenv

_REPO_ROOT = Path(__file__).parent.parent.parent
load_dotenv(_REPO_ROOT / ".env")

DEMO_FILES = _REPO_ROOT / "content-understanding" / "demo_files"

WORK_ORDER_PDF = DEMO_FILES / "work_order_fiber_splice.pdf"
WORK_ORDER_DOCX = DEMO_FILES / "work_order_fiber_splice.docx"
SCANNED_PNG = DEMO_FILES / "work_order_scanned.png"
TRAINING_CERT_PDF = DEMO_FILES / "safety_cert_splicing.pdf"

MIME_MAP = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}


@pytest.fixture(scope="session")
def cu_client():
    from azure.identity import AzureCliCredential
    from azure.ai.contentunderstanding import ContentUnderstandingClient

    endpoint = os.getenv("AZURE_CONTENTUNDERSTANDING_ENDPOINT", "").strip()
    if not endpoint:
        pytest.skip("AZURE_CONTENTUNDERSTANDING_ENDPOINT not set — skipping live CU tests")

    return ContentUnderstandingClient(endpoint=endpoint, credential=AzureCliCredential())


def analyze_binary(cu_client, analyzer_id: str, file_path: Path):
    """Helper: submit a file to an analyzer and return the raw result."""
    suffix = file_path.suffix.lower()
    content_type = MIME_MAP.get(suffix)
    if not content_type:
        raise ValueError(f"Unsupported file type: {suffix}")

    poller = cu_client.begin_analyze_binary(
        analyzer_id=analyzer_id,
        binary_input=file_path.read_bytes(),
        content_type=content_type,
    )
    return poller.result()


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


def get_fields_from_result(result) -> dict:
    """Extract all fields from the first content block of an analysis result."""
    if not result.contents:
        return {}
    content = result.contents[0]
    fields = getattr(content, "fields", None) or {}
    return {name: extract_field_value(f) for name, f in fields.items()}


def get_markdown_from_result(result) -> str:
    """Extract markdown text from the first content block of an analysis result."""
    if not result.contents:
        return ""
    content = result.contents[0]
    return getattr(content, "markdown", None) or ""


def get_category_from_result(result) -> str:
    """Extract the classification category from a classifier result."""
    if not result.contents:
        return ""
    content = result.contents[0]

    # Try segments first (segmented classification)
    segments = getattr(content, "segments", None)
    if segments:
        seg = segments[0]
        return getattr(seg, "category", "") or ""

    # Fall back to top-level category
    return getattr(content, "category", "") or ""
