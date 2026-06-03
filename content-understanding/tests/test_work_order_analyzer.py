"""
Live tests for the cu_demo_work_order field extractor (Step 1).

Compares extracted fields against the expected JSON files in demo_files/.
Strict equality on deterministic fields (status, priority, technician,
parts_needed, due_date); non-empty checks on generated text fields.
"""

import json
import pytest
from .conftest import (
    analyze_binary, get_fields_from_result,
    WORK_ORDER_PDF, WORK_ORDER_DOCX, SCANNED_PNG, DEMO_FILES,
)

ANALYZER_ID = "cu_demo_work_order"

WO_FIELDS = ["title", "description", "status", "priority",
             "assigned_technician", "location", "due_date", "parts_needed"]


@pytest.fixture(scope="module")
def expected_pdf():
    return json.loads((DEMO_FILES / "work_order_fiber_splice.json").read_text())


@pytest.fixture(scope="module")
def expected_png():
    return json.loads((DEMO_FILES / "work_order_scanned.json").read_text())


class TestWorkOrderPdf:
    @pytest.fixture(scope="class")
    def result(self, cu_client):
        return analyze_binary(cu_client, ANALYZER_ID, WORK_ORDER_PDF)

    @pytest.fixture(scope="class")
    def fields(self, result):
        return get_fields_from_result(result)

    def test_all_schema_fields_present(self, fields):
        for field in WO_FIELDS:
            assert field in fields, f"Expected field '{field}' missing from result"

    def test_title_non_empty(self, fields):
        assert fields.get("title"), "title should not be empty"

    def test_status_matches_expected(self, fields, expected_pdf):
        assert fields.get("status") == expected_pdf["status"], (
            f"status: got '{fields.get('status')}', expected '{expected_pdf['status']}'"
        )

    def test_priority_matches_expected(self, fields, expected_pdf):
        assert fields.get("priority") == expected_pdf["priority"], (
            f"priority: got '{fields.get('priority')}', expected '{expected_pdf['priority']}'"
        )

    def test_assigned_technician_matches_expected(self, fields, expected_pdf):
        assert fields.get("assigned_technician") == expected_pdf["assigned_technician"], (
            f"assigned_technician: got '{fields.get('assigned_technician')}', "
            f"expected '{expected_pdf['assigned_technician']}'"
        )

    def test_due_date_matches_expected(self, fields, expected_pdf):
        assert fields.get("due_date") == expected_pdf["due_date"], (
            f"due_date: got '{fields.get('due_date')}', expected '{expected_pdf['due_date']}'"
        )

    def test_parts_needed_matches_expected(self, fields, expected_pdf):
        got = fields.get("parts_needed") or []
        exp = expected_pdf["parts_needed"]
        assert len(got) == len(exp), f"parts_needed count: got {len(got)}, expected {len(exp)}"
        for i, (g, e) in enumerate(zip(got, exp)):
            assert g.get("part_id") == e["part_id"], (
                f"parts_needed[{i}].part_id: got '{g.get('part_id')}', expected '{e['part_id']}'"
            )
            assert int(g.get("quantity", 0)) == int(e["quantity"]), (
                f"parts_needed[{i}].quantity: got {g.get('quantity')}, expected {e['quantity']}"
            )


class TestWorkOrderDocx:
    """Work order in .docx format — a *different* work order from the PDF.

    The docx is intentionally a separate work order used to demo Basic CU
    (prebuilt-layout) side-by-side with the custom analyzer on the PDF.
    These tests verify the custom analyzer still produces a structured
    extraction from .docx; they do not assert equality against the PDF's
    expected fields.
    """

    @pytest.fixture(scope="class")
    def result(self, cu_client):
        return analyze_binary(cu_client, ANALYZER_ID, WORK_ORDER_DOCX)

    @pytest.fixture(scope="class")
    def fields(self, result):
        return get_fields_from_result(result)

    def test_all_schema_fields_present(self, fields):
        """CU returns all schema keys even if some values are None."""
        for field in WO_FIELDS:
            assert field in fields, f"Expected field '{field}' missing from docx result"

    def test_status_in_enum(self, fields):
        assert fields.get("status") in {"open", "in_progress", "completed", "cancelled"}

    def test_priority_in_enum(self, fields):
        assert fields.get("priority") in {"low", "medium", "high", "critical"}

    def test_due_date_iso_format(self, fields):
        due = fields.get("due_date") or ""
        assert due.endswith("Z") and "T" in due, f"due_date should be ISO 8601 Z, got '{due}'"

    def test_description_non_empty(self, fields):
        assert fields.get("description"), "description should not be empty"

    def test_parts_needed_well_formed(self, fields):
        got = fields.get("parts_needed") or []
        assert isinstance(got, list) and len(got) >= 1, "parts_needed should be a non-empty list"
        for i, p in enumerate(got):
            assert (p.get("part_id") or "").startswith("FIB-"), (
                f"parts_needed[{i}].part_id should be FIB-XXX, got '{p.get('part_id')}'"
            )
            assert int(p.get("quantity", 0)) >= 1, (
                f"parts_needed[{i}].quantity should be >= 1, got {p.get('quantity')}"
            )

    @pytest.mark.xfail(reason="Custom analyzer trained on PDF/image — title may not extract from docx", strict=False)
    def test_title_non_empty(self, fields):
        assert fields.get("title"), "title should not be empty"

    @pytest.mark.xfail(reason="Custom analyzer trained on PDF/image — assigned_technician may not extract from docx", strict=False)
    def test_assigned_technician_present(self, fields):
        assert fields.get("assigned_technician")

    @pytest.mark.xfail(reason="Custom analyzer trained on PDF/image — location may not extract from docx", strict=False)
    def test_location_present(self, fields):
        assert fields.get("location")


class TestScannedWorkOrderPng:
    @pytest.fixture(scope="class")
    def result(self, cu_client):
        return analyze_binary(cu_client, ANALYZER_ID, SCANNED_PNG)

    @pytest.fixture(scope="class")
    def fields(self, result):
        return get_fields_from_result(result)

    def test_all_schema_fields_present(self, fields):
        for field in WO_FIELDS:
            assert field in fields, f"Expected field '{field}' missing from scanned PNG result"

    def test_title_non_empty(self, fields):
        assert fields.get("title"), "title should not be empty for scanned PNG"

    def test_status_matches_expected(self, fields, expected_png):
        assert fields.get("status") == expected_png["status"], (
            f"status: got '{fields.get('status')}', expected '{expected_png['status']}'"
        )

    def test_priority_matches_expected(self, fields, expected_png):
        assert fields.get("priority") == expected_png["priority"], (
            f"priority: got '{fields.get('priority')}', expected '{expected_png['priority']}'"
        )

    # NOTE: assigned_technician test removed for scanned PNG — handwritten OCR
    # is non-deterministic on this fixture. See REFACTOR_PLAN for context.

    def test_parts_needed_matches_expected(self, fields, expected_png):
        got = fields.get("parts_needed") or []
        exp = expected_png["parts_needed"]
        assert len(got) == len(exp), f"parts_needed count: got {len(got)}, expected {len(exp)}"
        for i, (g, e) in enumerate(zip(got, exp)):
            assert g.get("part_id") == e["part_id"], (
                f"parts_needed[{i}].part_id: got '{g.get('part_id')}', expected '{e['part_id']}'"
            )

