"""Allowlisted data operations. Existing Supabase RLS/RPC policies are preserved."""
from __future__ import annotations
from typing import Any
from fastapi import HTTPException
from ..core.errors import error_message
from ..core.policies import ALLOWED_TABLES, ALLOWED_RPCS
from ..repositories.query import build_params
from ..repositories.supabase import SupabaseRepository, parse_response
from ..schemas.database import DbRequest

class DatabaseService:
    def __init__(self, repository: SupabaseRepository) -> None:
        self.repo = repository

    async def query(self, body: DbRequest, token: str | None) -> dict[str, Any]:
        if body.table not in ALLOWED_TABLES:
            raise HTTPException(400, "This table is not available through the BloodCare API.")
        method = {"select": "GET", "insert": "POST", "update": "PATCH", "delete": "DELETE"}[body.action]
        prefer = []
        if body.count == "exact":
            prefer.append("count=exact")
        if body.action != "select":
            prefer.append("return=representation")
        r = await self.repo.table(method, body.table, token=token, extra={"Prefer": ",".join(prefer)} if prefer else None, params=build_params(body), json=body.data if body.action in {"insert", "update"} else None)
        payload = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(payload, "Database request failed."))
        tail = r.headers.get("content-range", "").rsplit("/", 1)[-1]
        count = int(tail) if "/" in r.headers.get("content-range", "") and tail.isdigit() else None
        if body.head:
            payload = None
        elif body.single or body.maybe_single:
            rows = payload if isinstance(payload, list) else ([] if payload is None else [payload])
            if len(rows) == 1:
                payload = rows[0]
            elif not rows and body.maybe_single:
                payload = None
            elif not rows:
                raise HTTPException(406, "No record found.")
            else:
                raise HTTPException(406, "Expected a single record.")
        return {"data": payload, "count": count}

    async def rpc(self, name: str, payload: dict[str, Any], token: str | None) -> dict[str, Any]:
        if name not in ALLOWED_RPCS:
            raise HTTPException(400, "This RPC is not available through the BloodCare API.")
        r = await self.repo.rpc(name, payload or {}, token=token)
        data = await parse_response(r)
        if not r.is_success:
            raise HTTPException(r.status_code, error_message(data, f"RPC {name} failed."))
        return {"data": data}
