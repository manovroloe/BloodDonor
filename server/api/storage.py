"""Event-image upload/download boundary; file reads have an explicit size limit."""
from fastapi import APIRouter, Request, Response, UploadFile, File, Query
from ..core.security import token_from
from ..schemas.storage import RemoveStoragePayload
from ..services.storage import StorageService
from .dependencies import Repository
router = APIRouter(tags=["Storage"])

@router.post("/api/storage/upload/{bucket}/{path:path}")
async def storage_upload(bucket: str, path: str, request: Request, repo: Repository, file: UploadFile = File(...), upsert: bool = Query(False)):
    try:
        content = await file.read(repo.settings.max_upload_mb * 1024 * 1024 + 1)
    finally:
        await file.close()
    return await StorageService(repo).upload(bucket, path, content, file.content_type or "application/octet-stream", token_from(request), upsert)

@router.delete("/api/storage/{bucket}")
async def storage_remove(bucket: str, body: RemoveStoragePayload, request: Request, repo: Repository):
    return await StorageService(repo).remove(bucket, body.paths, token_from(request))

@router.get("/api/storage/public/{bucket}/{path:path}")
async def storage_public(bucket: str, path: str, repo: Repository):
    content, content_type = await StorageService(repo).public(bucket, path)
    return Response(content, media_type=content_type, headers={"Cache-Control": "public, max-age=3600"})
