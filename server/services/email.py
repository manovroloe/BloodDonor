"""SMTP adapter, executed in a worker thread by the contact-reply workflow."""
from email.message import EmailMessage
import smtplib
import ssl
from ..core.config import Settings

def send_contact_reply(settings: Settings, to_email: str, recipient_name: str, reply_text: str, inquiry_type: str) -> None:
    if not settings.smtp_configured:
        raise RuntimeError("Outgoing email is not configured. Add SMTP settings to the BloodCare .env file.")

    msg = EmailMessage()
    msg["Subject"] = f"BloodCare reply — {inquiry_type.replace('-', ' ').title()}"
    msg["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    msg["To"] = to_email
    msg.set_content(
        f"Hello {recipient_name or 'there'},\n\n"
        f"{reply_text.strip()}\n\n"
        "This reply was sent by the BloodCare administration team in response to your Contact BloodCare message.\n\n"
        "— BloodCare"
    )

    if settings.smtp_port == 465:
        with smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, context=ssl.create_default_context(), timeout=20) as smtp:
            if settings.smtp_username:
                smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(msg)
        return

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
        smtp.ehlo()
        if settings.smtp_use_tls:
            smtp.starttls(context=ssl.create_default_context())
            smtp.ehlo()
        if settings.smtp_username:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(msg)
