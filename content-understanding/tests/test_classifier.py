"""
Live tests for the cu_demo_classify_and_analyze classifier (Step 2).

Tests that work order documents are routed to 'work_order' and non-work-order
documents are routed to 'other'.

Note: with return_details=False the classifier returns only the category label —
sub-analyzer field extraction results are not included in this payload. Field
extraction is tested separately in test_work_order_analyzer.py.
"""

import pytest
from .conftest import (
    analyze_binary, get_category_from_result,
    WORK_ORDER_PDF, WORK_ORDER_DOCX, SCANNED_PNG, TRAINING_CERT_PDF,
)

CLASSIFIER_ID = "cu_demo_classify_and_analyze"


class TestClassification:
    def test_work_order_pdf_classified_as_work_order(self, cu_client):
        result = analyze_binary(cu_client, CLASSIFIER_ID, WORK_ORDER_PDF)
        category = get_category_from_result(result)
        assert category == "work_order", (
            f"Expected 'work_order' for work_order_fiber_splice.pdf, got '{category}'"
        )

    @pytest.mark.xfail(reason="Classifier trained on PDF/image work orders — docx may route to 'other'", strict=False)
    def test_work_order_docx_classified_as_work_order(self, cu_client):
        result = analyze_binary(cu_client, CLASSIFIER_ID, WORK_ORDER_DOCX)
        category = get_category_from_result(result)
        assert category == "work_order", (
            f"Expected 'work_order' for work_order_fiber_splice.docx, got '{category}'"
        )

    def test_scanned_png_classified_as_work_order(self, cu_client):
        result = analyze_binary(cu_client, CLASSIFIER_ID, SCANNED_PNG)
        category = get_category_from_result(result)
        assert category == "work_order", (
            f"Expected 'work_order' for work_order_scanned.png, got '{category}'"
        )

    def test_training_cert_classified_as_other(self, cu_client):
        result = analyze_binary(cu_client, CLASSIFIER_ID, TRAINING_CERT_PDF)
        category = get_category_from_result(result)
        assert category == "other", (
            f"Expected 'other' for safety_cert_splicing.pdf, got '{category}'"
        )

