"""Public contact submission; does not use an elevated database key."""
from __future__ import annotations
import re
from fastapi import HTTPException
from ..core.errors import error_message
from ..repositories.supabase import SupabaseRepository, parse_response
from ..schemas.contacts import ContactPayload

class ContactService:
    def __init__(self, repository: SupabaseRepository) -> None:
        self.repo = repository

    async def submit(self, body: ContactPayload, token: str | None, source_path: str) -> dict:
        full_name, email, phone, message = body.full_name.strip(), body.email.strip().lower(), body.phone.strip(), body.message.strip()
        if len(full_name) < 2:
            raise HTTPException(422, "Please enter your full name.")
        if "@" not in email or email.startswith("@") or email.endswith("@"):
            raise HTTPException(422, "Please enter a valid email address.")
        if not re.fullmatch(r"[0-9]{7,15}", phone):
            raise HTTPException(422, "Contact number must contain 7 to 15 digits only.")
        if len(message) < 10:
            raise HTTPException(422, "Please enter a message with at least 10 characters.")
        r = await self.repo.rpc("submit_contact_message", {"p_full_name": full_name, "p_email": email, "p_phone": phone, "p_inquiry_type": body.inquiry_type, "p_message": message, "p_source_page": body.source_page.strip() or source_path}, token=token)
        data = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(data, "Unable to send your message right now."))
        return {"ok": True, "id": data if isinstance(data, str) else None, "message": "Your message has been sent to BloodCare."}
