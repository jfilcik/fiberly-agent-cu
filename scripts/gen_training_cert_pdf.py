"""
Script to generate a mock Fiber Splicing Safety Training Certificate PDF.
Used to demonstrate the CU 'Classify & Analyze Work Order' mode returning
near-zero results — this document shares almost no schema overlap with work orders.

Run: uv run python scripts/gen_training_cert_pdf.py
Output: content-understanding/demo_files/safety_cert_splicing.pdf
"""

from pathlib import Path
from datetime import date
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
)

OUTPUT_DIR = Path(__file__).parent.parent / "content-understanding" / "demo_files"
OUTPUT_DIR.mkdir(exist_ok=True)
OUTPUT_PATH = OUTPUT_DIR / "safety_cert_splicing.pdf"

# ── Color palette (different from WO — warmer, institutional) ─────────────────
NAVY        = colors.HexColor("#1A3557")
GOLD        = colors.HexColor("#C8922A")
LIGHT_GOLD  = colors.HexColor("#FDF4E3")
MID_GRAY    = colors.HexColor("#CCCCCC")
DARK_GRAY   = colors.HexColor("#444444")
LIGHT_GRAY  = colors.HexColor("#F5F5F5")

# ── Certificate data ───────────────────────────────────────────────────────────
CERT = {
    "cert_id":          "CERT-2026-FST-0441",
    "trainee_name":     "R. Nguyen",
    "course_name":      "Fusion Splicing Safety & Certification — Level II",
    "course_code":      "FST-202",
    "issued_date":      "May 14, 2026",
    "expiry_date":      "May 14, 2028",
    "instructor":       "Dr. Sandra Okafor",
    "organization":     "Pacific Northwest Fiber Training Institute",
    "org_address":      "1800 Industry Lane, Suite 400 · Bellevue, WA 98004",
    "accreditation":    "BICSI Accredited · Course ID: BCS-4471",
    "hours":            "16 contact hours",
    "score":            "92 / 100",
    "modules": [
        ("FST-202-A", "Laser Safety & PPE Requirements",          "Pass"),
        ("FST-202-B", "Arc Fusion Splicer Operation & Calibration", "Pass"),
        ("FST-202-C", "Cleaving Techniques & Fiber Preparation",  "Pass"),
        ("FST-202-D", "OTDR Trace Interpretation",                "Pass"),
        ("FST-202-E", "Splice Enclosure & Vault Safety",          "Pass"),
        ("FST-202-F", "Incident Response & Emergency Procedures", "Pass"),
    ],
    "competencies": [
        "Safely operate Class 1M and Class 3B laser equipment",
        "Perform single-mode and multi-mode fusion splices to IL ≤ 0.10 dB",
        "Interpret OTDR loss signatures and identify splice anomalies",
        "Follow OSHA 1910.97 guidelines for non-ionizing radiation",
        "Complete post-splice enclosure sealing to IP68 standard",
    ],
}


def build_pdf():
    styles = getSampleStyleSheet()

    centered = ParagraphStyle("centered", parent=styles["Normal"],
                              alignment=TA_CENTER, fontName="Helvetica")
    small_center = ParagraphStyle("small_center", parent=centered,
                                  fontSize=9, textColor=DARK_GRAY)
    label_style = ParagraphStyle("label", parent=styles["Normal"],
                                 fontSize=8, textColor=colors.gray,
                                 fontName="Helvetica")
    value_style = ParagraphStyle("value", parent=styles["Normal"],
                                 fontSize=11, fontName="Helvetica-Bold",
                                 textColor=NAVY)
    section_header = ParagraphStyle("section_header", parent=styles["Normal"],
                                    fontSize=9, fontName="Helvetica-Bold",
                                    textColor=NAVY, spaceAfter=4)
    body_style = ParagraphStyle("body", parent=styles["Normal"],
                                fontSize=9, fontName="Helvetica",
                                textColor=DARK_GRAY, leading=14)

    doc = SimpleDocTemplate(
        str(OUTPUT_PATH),
        pagesize=LETTER,
        leftMargin=0.85 * inch,
        rightMargin=0.85 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
    )

    story = []
    W = LETTER[0] - 1.7 * inch  # usable width

    # ── Gold top bar ──────────────────────────────────────────────────────────
    story.append(Table(
        [[""]],
        colWidths=[W],
        rowHeights=[8],
        style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), GOLD)]),
    ))
    story.append(Spacer(1, 14))

    # ── Organization header ───────────────────────────────────────────────────
    story.append(Paragraph(CERT["organization"].upper(), ParagraphStyle(
        "org", parent=centered, fontSize=13, fontName="Helvetica-Bold",
        textColor=NAVY, spaceAfter=2,
    )))
    story.append(Paragraph(CERT["org_address"], small_center))
    story.append(Paragraph(CERT["accreditation"], ParagraphStyle(
        "accred", parent=small_center, fontSize=8,
        textColor=GOLD, spaceAfter=12,
    )))

    story.append(HRFlowable(width=W, color=GOLD, thickness=1.5))
    story.append(Spacer(1, 10))

    # ── Certificate title ─────────────────────────────────────────────────────
    story.append(Paragraph("CERTIFICATE OF COMPLETION", ParagraphStyle(
        "cert_title", parent=centered, fontSize=22, fontName="Helvetica-Bold",
        textColor=NAVY, spaceAfter=4,
    )))
    story.append(Paragraph("This certifies that", ParagraphStyle(
        "sub", parent=centered, fontSize=11, textColor=DARK_GRAY,
        fontName="Helvetica-Oblique", spaceAfter=6,
    )))
    story.append(Paragraph(CERT["trainee_name"], ParagraphStyle(
        "trainee", parent=centered, fontSize=28, fontName="Helvetica-Bold",
        textColor=GOLD, spaceAfter=4,
    )))
    story.append(Paragraph(
        f"has successfully completed the requirements for",
        ParagraphStyle("sub2", parent=centered, fontSize=11,
                       textColor=DARK_GRAY, spaceAfter=4)
    ))
    story.append(Paragraph(CERT["course_name"], ParagraphStyle(
        "course", parent=centered, fontSize=14, fontName="Helvetica-Bold",
        textColor=NAVY, spaceAfter=2,
    )))
    story.append(Paragraph(
        f"Course Code: {CERT['course_code']}  ·  {CERT['hours']}  ·  Final Score: {CERT['score']}",
        ParagraphStyle("meta", parent=centered, fontSize=9,
                       textColor=DARK_GRAY, spaceAfter=14)
    ))

    story.append(HRFlowable(width=W, color=MID_GRAY, thickness=0.5))
    story.append(Spacer(1, 12))

    # ── Issue / Expiry / Cert ID row ──────────────────────────────────────────
    meta_data = [
        [
            Paragraph("Date Issued", label_style),
            Paragraph("Expiry Date", label_style),
            Paragraph("Certificate ID", label_style),
        ],
        [
            Paragraph(CERT["issued_date"], value_style),
            Paragraph(CERT["expiry_date"], value_style),
            Paragraph(CERT["cert_id"], ParagraphStyle(
                "cert_id", parent=value_style, fontSize=9,
            )),
        ],
    ]
    meta_table = Table(meta_data, colWidths=[W / 3] * 3)
    meta_table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 2),
        ("TOPPADDING", (0, 1), (-1, 1), 0),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 14))

    # ── Module completion table ───────────────────────────────────────────────
    story.append(Paragraph("Modules Completed", section_header))
    mod_header = [
        Paragraph("Module ID", ParagraphStyle("th", parent=label_style, fontName="Helvetica-Bold")),
        Paragraph("Description", ParagraphStyle("th", parent=label_style, fontName="Helvetica-Bold")),
        Paragraph("Result", ParagraphStyle("th", parent=label_style, fontName="Helvetica-Bold")),
    ]
    mod_rows = [mod_header]
    for code, desc, result in CERT["modules"]:
        mod_rows.append([
            Paragraph(code, ParagraphStyle("mc", parent=body_style, fontSize=8, fontName="Helvetica-Bold")),
            Paragraph(desc, ParagraphStyle("md", parent=body_style, fontSize=8)),
            Paragraph(result, ParagraphStyle("mr", parent=body_style, fontSize=8,
                                             textColor=colors.HexColor("#1A7A3C"))),
        ])

    mod_table = Table(mod_rows, colWidths=[1.1 * inch, W - 2.1 * inch, 0.8 * inch])
    mod_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_GRAY]),
        ("GRID", (0, 0), (-1, -1), 0.4, MID_GRAY),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(mod_table)
    story.append(Spacer(1, 14))

    # ── Competencies ──────────────────────────────────────────────────────────
    story.append(Paragraph("Competencies Demonstrated", section_header))
    for comp in CERT["competencies"]:
        story.append(Paragraph(f"• {comp}", body_style))
    story.append(Spacer(1, 18))

    # ── Signature block ───────────────────────────────────────────────────────
    sig_data = [
        [
            Paragraph(CERT["instructor"], ParagraphStyle(
                "sig_name", parent=styles["Normal"], fontSize=11,
                fontName="Helvetica-Bold", textColor=NAVY,
            )),
            Paragraph("Authorized by PNFTI Registrar", ParagraphStyle(
                "sig_name2", parent=styles["Normal"], fontSize=11,
                fontName="Helvetica-Bold", textColor=NAVY,
            )),
        ],
        [
            Paragraph("Lead Instructor", label_style),
            Paragraph("Pacific Northwest Fiber Training Institute", label_style),
        ],
    ]
    sig_table = Table(sig_data, colWidths=[W / 2, W / 2])
    sig_table.setStyle(TableStyle([
        ("TOPPADDING", (0, 0), (-1, 0), 0),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 2),
        ("LINEABOVE", (0, 0), (0, 0), 0.75, DARK_GRAY),
        ("LINEABOVE", (1, 0), (1, 0), 0.75, DARK_GRAY),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 12),
    ]))
    story.append(sig_table)
    story.append(Spacer(1, 16))

    # ── Gold bottom bar ───────────────────────────────────────────────────────
    story.append(HRFlowable(width=W, color=GOLD, thickness=1.5))
    story.append(Spacer(1, 6))
    story.append(Paragraph(
        f"This certificate is the property of {CERT['organization']} and is non-transferable. "
        f"Verify authenticity at pnfti.example.org/verify using certificate ID {CERT['cert_id']}.",
        ParagraphStyle("footer", parent=centered, fontSize=7.5, textColor=colors.gray),
    ))

    doc.build(story)
    print(f"Generated: {OUTPUT_PATH}")


if __name__ == "__main__":
    build_pdf()
