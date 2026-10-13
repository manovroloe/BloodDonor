"""Event-image storage operations; normal requests retain user-scoped RLS."""
from __future__ import annotations
from typing import Any
from fastapi import HTTPException
from ..core.policies import ALLOWED_BUCKETS
from ..core.errors import error_message
from ..repositories.supabase import SupabaseRepository, parse_response

class StorageService:
    def __init__(self, repository: SupabaseRepository) -> None:
        self.repo = repository

    def require_bucket(self, bucket: str, *, public: bool = False) -> None:
        if bucket not in ALLOWED_BUCKETS:
            raise HTTPException(404 if public else 400, "Storage bucket is not available through the BloodCare API.")

    async def upload(self, bucket: str, path: str, content: bytes, content_type: str, token: str | None, upsert: bool) -> dict[str, Any]:
        self.require_bucket(bucket)
        if not token:
            raise HTTPException(401, "Login required.")
        if len(content) > self.repo.settings.max_upload_mb * 1024 * 1024:
            raise HTTPException(413, "The image exceeds the website upload limit.")
        r = await self.repo.upload(bucket, path, content, content_type, token=token, upsert=upsert)
        data = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(data, "Image upload failed."))
        return {"data": data, "public_url": f"/api/storage/public/{bucket}/{self.repo.object_path(path)}"}

    async def remove(self, bucket: str, paths: list[str], token: str | None) -> dict[str, Any]:
        self.require_bucket(bucket)
        if not token:
            raise HTTPException(401, "Login required.")
        r = await self.repo.remove(bucket, paths, token=token)
        data = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(data, "Unable to remove stored file."))
        return {"data": data}

    async def public(self, bucket: str, path: str) -> tuple[bytes, str]:
        self.require_bucket(bucket, public=True)
        r = await self.repo.public_object(bucket, path)
        if not r.is_success:
            raise HTTPException(r.status_code, "Stored file was not found.")
        return r.content, r.headers.get("content-type", "application/octet-stream")
