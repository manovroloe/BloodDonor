"""Stable v22 JSON data contracts."""
from typing import Any
from fastapi import APIRouter, Request
from ..core.security import token_from
from ..schemas.database import DbRequest
from ..services.database import DatabaseService
from .dependencies import Repository
router = APIRouter(tags=["Data"])

@router.post("/api/db")
async def database(body: DbRequest, request: Request, repo: Repository):
    return await DatabaseService(repo).query(body, token_from(request))

@router.post("/api/rpc/{function_name}")
async def rpc(function_name: str, payload: dict[str, Any], request: Request, repo: Repository):
    return await DatabaseService(repo).rpc(function_name, payload, token_from(request))
