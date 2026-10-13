"""Only this repository knows Supabase HTTP endpoints and authorization headers.

User requests always use the public key plus the user's token, never the admin key.
No startup DDL, seeding, migration, or local data copy is performed here.
"""
from __future__ import annotations
from typing import Any
from urllib.parse import quote
import httpx
from fastapi import HTTPException
from ..core.config import Settings

async def parse_response(response: httpx.Response) -> Any:
    if not response.content:
        return None
    try:
        return response.json()
    except ValueError:
        return response.text

class SupabaseRepository:
    def __init__(self, http: httpx.AsyncClient, settings: Settings) -> None:
        self.http = http
        self.settings = settings

    def require_config(self) -> None:
        if not self.settings.configured:
            raise HTTPException(503, "BloodCare is not configured yet. Please contact the website administrator.")

    def headers(self, token: str | None = None, *, admin: bool = False, auth: bool = False, extra: dict[str, str] | None = None) -> dict[str, str]:
        self.require_config()
        key = self.settings.supabase_anon_key
        if admin:
            if not self.settings.auth_admin_configured:
                raise HTTPException(503, "Staff account management has not been configured by the website administrator.")
            key = self.settings.supabase_service_role_key
        result = {"apikey": key}
        # New sb_publishable_/sb_secret_ keys are API keys, not JWT bearer tokens.
        bearer = token if not admin else None
        if not bearer and (admin or not auth) and not key.startswith(("sb_publishable_", "sb_secret_")):
            bearer = key
        if bearer:
            result["Authorization"] = f"Bearer {bearer}"
        if extra:
            result.update(extra)
        return result

    async def auth(self, method: str, path: str, *, token: str | None = None, admin: bool = False, **kwargs: Any) -> httpx.Response:
        return await self.http.request(method, f"{self.settings.supabase_url}/auth/v1/{path.lstrip('/')}", headers=self.headers(token, admin=admin, auth=True), **kwargs)

    async def table(self, method: str, name: str, *, token: str | None = None, extra: dict[str, str] | None = None, **kwargs: Any) -> httpx.Response:
        return await self.http.request(method, f"{self.settings.supabase_url}/rest/v1/{quote(name, safe='')}", headers=self.headers(token, extra=extra), **kwargs)

    async def rpc(self, name: str, payload: dict[str, Any], *, token: str | None = None) -> httpx.Response:
        return await self.http.post(f"{self.settings.supabase_url}/rest/v1/rpc/{quote(name, safe='')}", headers=self.headers(token), json=payload)

    @staticmethod
    def object_path(path: str) -> str:
        if not path or any(p in {"", ".", ".."} for p in path.split("/")) or "\\" in path or "\x00" in path:
            raise HTTPException(400, "Invalid storage path.")
        return "/".join(quote(part, safe="") for part in path.split("/"))

    async def upload(self, bucket: str, path: str, content: bytes, content_type: str, *, token: str | None, upsert: bool) -> httpx.Response:
        safe_path = self.object_path(path)
        return await self.http.post(f"{self.settings.supabase_url}/storage/v1/object/{quote(bucket, safe='')}/{safe_path}", headers=self.headers(token, extra={"Content-Type": content_type, "x-upsert": "true" if upsert else "false"}), content=content)

    async def remove(self, bucket: str, paths: list[str], *, token: str | None) -> httpx.Response:
        for path in paths:
            self.object_path(path)
        return await self.http.request("DELETE", f"{self.settings.supabase_url}/storage/v1/object/{quote(bucket, safe='')}", headers=self.headers(token), json={"prefixes": paths})

    async def public_object(self, bucket: str, path: str) -> httpx.Response:
        self.require_config()
        return await self.http.get(f"{self.settings.supabase_url}/storage/v1/object/public/{quote(bucket, safe='')}/{self.object_path(path)}")
