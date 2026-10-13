"""Authentication workflows; user identity/permissions remain enforced by Supabase."""
from __future__ import annotations
from typing import Any
import logging
import httpx
from fastapi import HTTPException
from ..core.errors import error_message
from ..repositories.supabase import SupabaseRepository, parse_response
from ..schemas.auth import AuthCredentials, SignUpPayload

logger = logging.getLogger(__name__)

class AuthService:
    def __init__(self, repository: SupabaseRepository) -> None:
        self.repo = repository

    async def sign_in(self, credentials: AuthCredentials) -> dict[str, Any]:
        r = await self.repo.auth("POST", "token", params={"grant_type": "password"}, json={"email": credentials.email.strip().lower(), "password": credentials.password})
        payload = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(payload, "Unable to sign in."))
        if not isinstance(payload, dict):
            raise HTTPException(502, "Invalid sign-in response.")
        token, user = payload.get("access_token"), payload.get("user") or {}
        if token and user.get("id"):
            staff = await self.repo.table("GET", "staff_profiles", token=token, params={"select": "id,active,role", "id": f"eq.{user['id']}", "limit": "1"})
            rows = await parse_response(staff)
            if not staff.is_success:
                await self.revoke(token)
                raise HTTPException(503, "BloodCare could not verify account access. Please try again.")
            profile = rows[0] if isinstance(rows, list) and rows else None
            if profile and not profile.get("active"):
                await self.revoke(token)
                raise HTTPException(403, "This staff account is disabled. Contact a BloodCare administrator.")
        return payload

    async def sign_up(self, credentials: SignUpPayload) -> dict[str, Any]:
        r = await self.repo.auth("POST", "signup", json={"email": credentials.email.strip().lower(), "password": credentials.password, "data": {"full_name": credentials.full_name.strip()}})
        payload = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(payload, "Unable to create account."))
        if not isinstance(payload, dict):
            raise HTTPException(502, "Invalid registration response.")
        return payload

    async def refresh(self, refresh_token: str | None) -> dict[str, Any]:
        if not refresh_token:
            raise HTTPException(401, "No refresh session is available.")
        r = await self.repo.auth("POST", "token", params={"grant_type": "refresh_token"}, json={"refresh_token": refresh_token})
        payload = await parse_response(r)
        if not r.is_success:
            # Only invalidate cookies for rejected credentials, not an upstream outage.
            if r.status_code in {400, 401, 403}:
                raise HTTPException(401, "Session expired.")
            raise HTTPException(503, "BloodCare could not renew your session. Please try again.")
        if not isinstance(payload, dict) or not payload.get("access_token"):
            raise HTTPException(502, "Invalid session response.")
        return payload

    async def user(self, token: str | None) -> dict[str, Any] | None:
        if not token:
            return None
        r = await self.repo.auth("GET", "user", token=token)
        payload = await parse_response(r)
        if r.status_code == 401:
            raise HTTPException(401, "Session expired.")
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(payload, "Unable to read session."))
        if not isinstance(payload, dict):
            raise HTTPException(502, "Invalid account response.")
        return payload

    async def revoke(self, token: str | None) -> None:
        if not token or not self.repo.settings.configured:
            return
        try:
            await self.repo.auth("POST", "logout", token=token, timeout=2.0)
        except httpx.RequestError:
            logger.warning("Upstream logout unavailable; local session will still be cleared.")

    async def require_admin(self, token: str | None) -> dict[str, Any]:
        if not token:
            raise HTTPException(401, "Administrator login required.")
        user = await self.user(token)
        if not user or not user.get("id"):
            raise HTTPException(401, "Administrator session expired.")
        r = await self.repo.table("GET", "staff_profiles", token=token, params={"select": "id,email,full_name,role,active", "id": f"eq.{user['id']}", "limit": "1"})
        rows = await parse_response(r)
        profile = rows[0] if r.is_success and isinstance(rows, list) and rows else None
        if not profile or not profile.get("active") or profile.get("role") != "admin":
            raise HTTPException(403, "Administrator access required.")
        return {"user": user, "profile": profile, "token": token}
