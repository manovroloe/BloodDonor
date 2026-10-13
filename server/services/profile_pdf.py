"""Existing v22 profile ticket renderer; layout intentionally unchanged."""
from __future__ import annotations
from datetime import datetime
from html import escape as html_escape
from io import BytesIO
from typing import Any
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether

def _profile_pdf_date(value: Any) -> str:
    if value in (None, "", "null"):
        return "-"
    raw = str(value)
    try:
        return datetime.fromisoformat(raw[:10]).strftime("%b %d, %Y")
    except Exception:
        return raw


def _profile_pdf_text(value: Any, default: str = "-") -> str:
    if value is None or value == "":
        return html_escape(default)
    return html_escape(str(value))


def build_profile_pdf(payload: dict[str, Any]) -> bytes:
    account = payload.get("account") or {}
    donor = payload.get("profile") or None
    requests = payload.get("requests") or []
    appointments = payload.get("appointments") or []
    donations = payload.get("donations") or []

    if donor:
        name = _profile_pdf_text(account.get("full_name") or f"{donor.get('first_name') or ''} {donor.get('last_name') or ''}".strip(), "BloodCare Donor")
        donor_code = _profile_pdf_text(donor.get("donor_code"), "BloodCare Donor")
        email = _profile_pdf_text(account.get("email") or donor.get("email"), "-")
    else:
        name = _profile_pdf_text(account.get("full_name") or account.get("email"), "BloodCare Account")
        donor_code = "BloodCare Account"
        email = _profile_pdf_text(account.get("email"), "-")

    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=16 * mm,
        leftMargin=16 * mm,
        topMargin=14 * mm,
        bottomMargin=14 * mm,
        title=f"BloodCare Profile - {name}",
        author="BloodCare",
    )

    styles = getSampleStyleSheet()
    red = colors.HexColor("#9F1239")
    red_dark = colors.HexColor("#7F1D32")
    rose = colors.HexColor("#FFF1F2")
    rose_2 = colors.HexColor("#FFE4E6")
    ink = colors.HexColor("#2F2023")
    muted = colors.HexColor("#725E63")
    border = colors.HexColor("#EADFE1")

    title_white = ParagraphStyle("BCHeaderTitle", parent=styles["Heading1"], fontName="Helvetica-Bold", fontSize=21, leading=24, textColor=colors.white, spaceAfter=4)
    sub_white = ParagraphStyle("BCHeaderSub", parent=styles["BodyText"], fontName="Helvetica", fontSize=9, leading=13, textColor=colors.HexColor("#FFE4E6"))
    section = ParagraphStyle("BCSection", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=12.5, leading=15, textColor=red_dark, spaceBefore=0, spaceAfter=7)
    body = ParagraphStyle("BCBody", parent=styles["BodyText"], fontName="Helvetica", fontSize=9, leading=12, textColor=ink)
    label = ParagraphStyle("BCLabel", parent=body, fontName="Helvetica-Bold", fontSize=7.4, leading=9, textColor=muted)
    value = ParagraphStyle("BCValue", parent=body, fontName="Helvetica-Bold", fontSize=9, leading=12, textColor=ink)
    metric = ParagraphStyle("BCMetric", parent=body, fontName="Helvetica-Bold", fontSize=15, leading=18, textColor=red)
    tiny = ParagraphStyle("BCTiny", parent=body, fontSize=7.2, leading=9, textColor=muted)

    story = []
    header = Table([[Paragraph(name, title_white)], [Paragraph(f"{donor_code} &nbsp;&nbsp;|&nbsp;&nbsp; {email}", sub_white)]], colWidths=[178 * mm])
    header.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), red),
        ("LEFTPADDING", (0, 0), (-1, -1), 16),
        ("RIGHTPADDING", (0, 0), (-1, -1), 16),
        ("TOPPADDING", (0, 0), (-1, 0), 14),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 2),
        ("TOPPADDING", (0, 1), (-1, 1), 0),
        ("BOTTOMPADDING", (0, 1), (-1, 1), 13),
    ]))
    story.extend([header, Spacer(1, 7 * mm)])

    if donor:
        story.append(Paragraph("Donor Details", section))
        detail_rows = [
            [Paragraph("DONOR CODE", label), Paragraph(donor_code, value), Paragraph("BLOOD TYPE", label), Paragraph(_profile_pdf_text(donor.get("blood_type")), value)],
            [Paragraph("WEIGHT", label), Paragraph(f"{_profile_pdf_text(donor.get('weight_kg'))} kg", value), Paragraph("BIRTH DATE", label), Paragraph(_profile_pdf_date(donor.get("birth_date")), value)],
            [Paragraph("LAST DONATION", label), Paragraph(_profile_pdf_date(donor.get("last_donation_date")), value), Paragraph("EST. NEXT ELIGIBILITY", label), Paragraph(_profile_pdf_date(donor.get("next_eligible_date")), value)],
        ]
        details = Table(detail_rows, colWidths=[28*mm, 58*mm, 34*mm, 58*mm])
        details.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF8F8")),
            ("BOX", (0, 0), (-1, -1), .6, border),
            ("INNERGRID", (0, 0), (-1, -1), .35, border),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 8),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ]))
        story.extend([details, Spacer(1, 5 * mm), Paragraph("Donor Summary", section)])

        summary_cells = [
            [Paragraph(_profile_pdf_text(donor.get("blood_type")), metric), Paragraph(str(len(donations)), metric), Paragraph(str(len(appointments)), metric), Paragraph(_profile_pdf_text(donor.get("status"), "pending").replace("_", " ").title(), metric)],
            [Paragraph("Blood Type", tiny), Paragraph("Verified Donations", tiny), Paragraph("Appointments", tiny), Paragraph("Eligibility Status", tiny)],
        ]
        summary = Table(summary_cells, colWidths=[44.5*mm]*4)
        summary.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), rose),
            ("BOX", (0, 0), (-1, -1), .7, rose_2),
            ("INNERGRID", (0, 0), (-1, -1), .4, rose_2),
            ("ALIGN", (0, 0), (-1, -1), "CENTER"),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, 0), 9),
            ("BOTTOMPADDING", (0, 0), (-1, 0), 2),
            ("TOPPADDING", (0, 1), (-1, 1), 0),
            ("BOTTOMPADDING", (0, 1), (-1, 1), 8),
        ]))
        story.extend([summary, Spacer(1, 6 * mm)])
    else:
        no_donor = Table([[Paragraph("This BloodCare account is not yet registered as a donor.", body)]], colWidths=[178*mm])
        no_donor.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,-1),rose),("BOX",(0,0),(-1,-1),.7,rose_2),("LEFTPADDING",(0,0),(-1,-1),10),("RIGHTPADDING",(0,0),(-1,-1),10),("TOPPADDING",(0,0),(-1,-1),10),("BOTTOMPADDING",(0,0),(-1,-1),10)]))
        story.extend([no_donor, Spacer(1, 6*mm)])

    def latest_table(title: str, headers: list[str], values: list[str] | None):
        block = [Paragraph(title, section)]
        if not values:
            t = Table([[Paragraph(f"No {title.lower()} record is available yet.", body)]], colWidths=[178*mm])
            t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,-1),colors.HexColor("#FFF8F8")),("BOX",(0,0),(-1,-1),.6,border),("LEFTPADDING",(0,0),(-1,-1),9),("RIGHTPADDING",(0,0),(-1,-1),9),("TOPPADDING",(0,0),(-1,-1),8),("BOTTOMPADDING",(0,0),(-1,-1),8)]))
            block.extend([t, Spacer(1, 5*mm)])
            return block
        count = len(headers)
        widths = [178*mm/count]*count
        t = Table([[Paragraph(h.upper(), label) for h in headers], [Paragraph(v, body) for v in values]], colWidths=widths, repeatRows=1)
        t.setStyle(TableStyle([
            ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#F6E8EB")),
            ("BACKGROUND", (0,1), (-1,1), colors.white),
            ("BOX", (0,0), (-1,-1), .6, border),
            ("INNERGRID", (0,0), (-1,-1), .35, border),
            ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
            ("LEFTPADDING", (0,0), (-1,-1), 7),
            ("RIGHTPADDING", (0,0), (-1,-1), 7),
            ("TOPPADDING", (0,0), (-1,-1), 7),
            ("BOTTOMPADDING", (0,0), (-1,-1), 7),
        ]))
        block.extend([t, Spacer(1, 5*mm)])
        return block

    latest_request = requests[0] if requests else None
    latest_appointment = appointments[0] if appointments else None
    latest_donation = donations[0] if donations else None

    story.extend(latest_table("Latest Blood Request", ["Reference","Patient","Blood","Needed","Status"], None if not latest_request else [
        _profile_pdf_text(latest_request.get("request_code")),
        _profile_pdf_text(latest_request.get("patient_name")),
        f"{_profile_pdf_text(latest_request.get('blood_type'))} - {_profile_pdf_text(latest_request.get('bags'), '0')} bag(s)",
        _profile_pdf_date(latest_request.get("date_needed")),
        _profile_pdf_text(latest_request.get("status"), "pending").replace("_", " ").title(),
    ]))
    story.extend(latest_table("Latest Appointment", ["Reference","Schedule","Location","Status"], None if not latest_appointment else [
        _profile_pdf_text(latest_appointment.get("appointment_code")),
        f"{_profile_pdf_date(latest_appointment.get('appointment_date'))} {_profile_pdf_text(latest_appointment.get('appointment_time'), '')[:5]}",
        _profile_pdf_text(latest_appointment.get("location")),
        _profile_pdf_text(latest_appointment.get("status"), "pending").replace("_", " ").title(),
    ]))
    story.extend(latest_table("Latest Donation", ["Donation ID","Date","Blood Type","Bags","Site"], None if not latest_donation else [
        _profile_pdf_text(latest_donation.get("donation_code")),
        _profile_pdf_date(latest_donation.get("donation_date")),
        _profile_pdf_text(latest_donation.get("blood_type")),
        _profile_pdf_text(latest_donation.get("bags"), "0"),
        _profile_pdf_text(latest_donation.get("donation_site")),
    ]))

    story.append(Spacer(1, 2*mm))
    story.append(Paragraph("Generated by BloodCare. Staff screening and verified system records remain authoritative.", tiny))
    doc.build(story)
    return buffer.getvalue()
