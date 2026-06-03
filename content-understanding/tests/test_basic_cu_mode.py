"""
Live tests for the Basic CU demo mode (prebuilt-layout analyzer).

Covers:
  - Work order PDF/PNG → markdown returned, no structured fields (correct for Basic CU mode)
  - Training cert → partial/mismatched extraction when passed to work order analyzer
    (intentional demo contrast: wrong analyzer on wrong doc type)
"""

import json
import pytest
from .conftest import (
    analyze_binary, get_fields_from_result, get_markdown_from_result,
    WORK_ORDER_PDF, SCANNED_PNG, TRAINING_CERT_PDF, DEMO_FILES,
)

PREBUILT_LAYOUT = "prebuilt-layout"
WO_ANALYZER = "cu_demo_work_order"


class TestBasicCuMode:
    """Basic CU (prebuilt-layout) on work order documents returns markdown, not structured fields."""

    def test_work_order_pdf_returns_markdown(self, cu_client):
        result = analyze_binary(cu_client, PREBUILT_LAYOUT, WORK_ORDER_PDF)
        md = get_markdown_from_result(result)
        assert md, "prebuilt-layout should return non-empty markdown for work_order_for_custom_analyzer.pdf"

    def test_work_order_pdf_markdown_contains_key_terms(self, cu_client):
        result = analyze_binary(cu_client, PREBUILT_LAYOUT, WORK_ORDER_PDF)
        md = get_markdown_from_result(result).lower()
        # Key terms that should appear in the OCR'd work order markdown
        for term in ["fiber", "splice", "springfield"]:
            assert term in md, f"Expected '{term}' in prebuilt-layout markdown output"

    def test_work_order_pdf_no_structured_fields(self, cu_client):
        result = analyze_binary(cu_client, PREBUILT_LAYOUT, WORK_ORDER_PDF)
        fields = get_fields_from_result(result)
        assert not fields, "prebuilt-layout should NOT return structured fields"

    def test_scanned_png_returns_markdown(self, cu_client):
        result = analyze_binary(cu_client, PREBUILT_LAYOUT, SCANNED_PNG)
        md = get_markdown_from_result(result)
        assert md, "prebuilt-layout should return non-empty markdown for work_order_scanned.png"

    def test_scanned_png_no_structured_fields(self, cu_client):
        result = analyze_binary(cu_client, PREBUILT_LAYOUT, SCANNED_PNG)
        fields = get_fields_from_result(result)
        assert not fields, "prebuilt-layout should NOT return structured fields for scanned PNG"


class TestWrongAnalyzerOnCert:
    """
    Demo contrast: training cert passed through the work order analyzer.
    Extraction should succeed but produce mismatched/partial data —
    demonstrating why classification matters.
    """

    @pytest.fixture(scope="class")
    def fields(self, cu_client):
        result = analyze_binary(cu_client, WO_ANALYZER, TRAINING_CERT_PDF)
        return get_fields_from_result(result)

    def test_schema_fields_returned(self, fields):
        # Analyzer always returns all schema keys, even if values are wrong
        wo_fields = ["title", "description", "status", "priority",
                     "assigned_technician", "location", "due_date", "parts_needed"]
        for field in wo_fields:
            assert field in fields, f"Expected schema field '{field}' in result"

    def test_parts_needed_empty_or_wrong(self, fields):
        # A training cert has no FIB-XXX parts — list should be empty or contain garbage
        expected_pdf = json.loads((DEMO_FILES / "work_order_fiber_splice.json").read_text())
        parts = fields.get("parts_needed") or []
        valid_part_ids = {p["part_id"] for p in expected_pdf["parts_needed"]}
        extracted_ids = {p.get("part_id") for p in parts if isinstance(p, dict)}
        # No valid WO part IDs should appear in a training cert
        overlap = valid_part_ids & extracted_ids
        assert not overlap, (
            f"Training cert should not produce valid WO part IDs, but got: {overlap}"
        )

    def test_technician_not_a_technician(self, fields):
        # The cert has a course instructor/issuer, not a field technician — just verify it differs
        # from the expected WO technician
        expected_pdf = json.loads((DEMO_FILES / "work_order_fiber_splice.json").read_text())
        cert_technician = fields.get("assigned_technician")
        wo_technician = expected_pdf["assigned_technician"]
        assert cert_technician != wo_technician, (
            f"Training cert should not extract the same technician as the work order; "
            f"got '{cert_technician}'"
        )
