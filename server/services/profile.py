"""Profile retrieval and PDF workflow with one session-refresh retry."""
from __future__ import annotations
import asyncio
import re
from dataclasses import dataclass
from typing import Any
from fastapi import HTTPException
from ..core.errors import error_message
from ..repositories.supabase import SupabaseRepository, parse_response
from .auth import AuthService
from .profile_pdf import build_profile_pdf

@dataclass
class ProfileTicket:
    content: bytes
    filename: str
    refreshed_auth: dict[str, Any] | None = None

class ProfileService:
    def __init__(self, repository: SupabaseRepository) -> None:
        self.repo = repository
        self.auth = AuthService(repository)

    async def ticket(self, token: str | None, refresh_token: str | None) -> ProfileTicket:
        self.repo.require_config()
        refreshed = None
        if not token and refresh_token:
            refreshed = await self.auth.refresh(refresh_token)
            token = refreshed.get("access_token")
        if not token:
            raise HTTPException(401, "Login required.")
        r = await self.repo.rpc("my_bloodcare_profile", {}, token=token)
        if r.status_code == 401 and refresh_token and not refreshed:
            refreshed = await self.auth.refresh(refresh_token)
            token = refreshed.get("access_token")
            r = await self.repo.rpc("my_bloodcare_profile", {}, token=token)
        payload = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(payload, "Unable to build your BloodCare profile PDF."))
        if not isinstance(payload, dict):
            raise HTTPException(502, "BloodCare profile data is unavailable.")
        content = await asyncio.to_thread(build_profile_pdf, payload)
        donor = payload.get("profile") or {}
        code = re.sub(r"[^A-Za-z0-9_-]+", "_", str(donor.get("donor_code") or "Account"))
        return ProfileTicket(content, f"BloodCare_Profile_{code}.pdf", refreshed)
