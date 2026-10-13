"""Administrator workflows. Elevated Auth access is gated by an active admin profile."""
from __future__ import annotations
import asyncio
import logging
from datetime import datetime, timezone
from typing import Any
from fastapi import HTTPException
from ..core.errors import error_message
from ..repositories.supabase import SupabaseRepository, parse_response
from ..schemas.admin import AdminStaffCreatePayload, AdminStaffPasswordPayload
from ..schemas.contacts import ContactReplyPayload
from .auth import AuthService
from .email import send_contact_reply

logger = logging.getLogger(__name__)

class AdminService:
    def __init__(self, repository: SupabaseRepository) -> None:
        self.repo = repository
        self.auth = AuthService(repository)

    async def config(self, token: str | None) -> dict[str, bool]:
        await self.auth.require_admin(token)
        return {"staff_auth_ready": self.repo.settings.auth_admin_configured, "email_reply_ready": self.repo.settings.smtp_configured}

    async def _rollback_auth_user(self, user_id: str) -> None:
        try:
            r = await self.repo.auth("DELETE", f"admin/users/{user_id}", admin=True)
            if not r.is_success:
                logger.error("Staff provisioning rollback failed; administrator review is required.")
        except Exception:
            logger.error("Staff provisioning rollback unavailable; administrator review is required.")

    async def create_staff(self, body: AdminStaffCreatePayload, token: str | None) -> dict[str, Any]:
        admin = await self.auth.require_admin(token)
        email, full_name = body.email.strip().lower(), body.full_name.strip()
        if "@" not in email or email.startswith("@") or email.endswith("@"):
            raise HTTPException(422, "Please enter a valid staff email address.")
        if body.password != body.confirm_password:
            raise HTTPException(422, "Password and confirmation do not match.")
        r = await self.repo.auth("POST", "admin/users", admin=True, json={"email": email, "password": body.password, "email_confirm": True, "user_metadata": {"full_name": full_name, "bloodcare_role": body.role}})
        created = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(created, "Unable to create the Supabase staff login."))
        user_id = (created.get("id") or (created.get("user") or {}).get("id")) if isinstance(created, dict) else None
        if not user_id:
            raise HTTPException(502, "Supabase created the account but did not return a user ID.")
        try:
            linked = await self.repo.rpc("admin_link_staff_by_email", {"p_email": email, "p_full_name": full_name, "p_role": body.role}, token=admin["token"])
            if not linked.is_success:
                raise HTTPException(linked.status_code, error_message(await parse_response(linked), "Staff login was created but could not be linked to BloodCare."))
            assigned = await self.repo.rpc("admin_set_staff_facilities", {"p_staff_id": user_id, "p_facility_ids": [body.primary_facility_id], "p_primary_facility": body.primary_facility_id}, token=admin["token"])
            if not assigned.is_success:
                raise HTTPException(assigned.status_code, error_message(await parse_response(assigned), "Staff login was created but the facility assignment failed."))
        except Exception:
            await self._rollback_auth_user(str(user_id))
            raise
        return {"ok": True, "id": user_id, "message": "Staff login created, assigned to a facility, and authorized."}

    async def reset_password(self, staff_id: str, body: AdminStaffPasswordPayload, token: str | None) -> dict[str, Any]:
        admin = await self.auth.require_admin(token)
        if not self.repo.settings.auth_admin_configured:
            raise HTTPException(503, "Staff password reset has not been configured by the website administrator.")
        r = await self.repo.table("GET", "staff_profiles", token=admin["token"], params={"select": "id", "id": f"eq.{staff_id}", "limit": "1"})
        rows = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(rows, "Unable to verify the staff account."))
        if not isinstance(rows, list) or not rows:
            raise HTTPException(404, "Staff account not found.")
        if body.password != body.confirm_password:
            raise HTTPException(422, "Password and confirmation do not match.")
        r = await self.repo.auth("PUT", f"admin/users/{staff_id}", admin=True, json={"password": body.password})
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(await parse_response(r), "Unable to set the staff password."))
        return {"ok": True, "message": "Staff password updated."}

    async def reply(self, contact_id: str, body: ContactReplyPayload, token: str | None) -> dict[str, Any]:
        admin = await self.auth.require_admin(token)
        reply_text = body.message.strip()
        if len(reply_text) < 2:
            raise HTTPException(422, "Reply message is required.")
        r = await self.repo.table("GET", "contact_messages", token=admin["token"], params={"select": "*", "id": f"eq.{contact_id}", "limit": "1"})
        contacts = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(contacts, "Unable to load the contact message."))
        contact = contacts[0] if isinstance(contacts, list) and contacts else None
        if not contact:
            raise HTTPException(404, "Contact message not found.")
        try:
            await asyncio.to_thread(send_contact_reply, self.repo.settings, str(contact.get("email") or "").strip(), str(contact.get("full_name") or "").strip(), reply_text, str(contact.get("inquiry_type") or "general"))
        except Exception as exc:
            logger.error("Contact reply email delivery failed (%s).", type(exc).__name__)
            raise HTTPException(503, "Email could not be sent. Please contact the website administrator or try again later.") from exc
        now = datetime.now(timezone.utc).isoformat()
        r = await self.repo.table("PATCH", "contact_messages", token=admin["token"], extra={"Prefer": "return=representation"}, params={"id": f"eq.{contact_id}"}, json={"status": "replied", "reply_message": reply_text, "replied_at": now, "replied_by": admin["user"]["id"], "email_delivery_status": "sent", "updated_at": now})
        updated = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(updated, "Email was sent, but BloodCare could not save the reply status."))
        return {"ok": True, "message": "Reply sent by email.", "data": updated[0] if isinstance(updated, list) and updated else updated}
