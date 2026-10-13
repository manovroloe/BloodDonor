"""Separate process liveness from actual Supabase database readiness."""
from time import monotonic
import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from .. import __version__
from .dependencies import Repository
router = APIRouter(tags=["Operations"])

@router.get("/api/health")
async def health(repo: Repository):
    return {"ok": True, "version": __version__, "supabase_configured": repo.settings.configured, "architecture": "HTML/CSS/JS -> JSON -> FastAPI -> Supabase"}

@router.get("/api/ready")
async def ready(request: Request, repo: Repository):
    if not repo.settings.configured:
        return JSONResponse(status_code=503, content={"ok": False, "database": "not_configured"})
    # Prevent health polling from creating unnecessary database traffic.
    async with request.app.state.readiness_lock:
        cached = request.app.state.readiness_cache
        if cached and monotonic() - cached[0] < 10:
            return JSONResponse(status_code=cached[1], content=cached[2])
        try:
            response = await repo.table("GET", "facilities", params={"select": "id", "limit": "1"}, timeout=5.0)
            ok = response.is_success
        except httpx.RequestError:
            ok = False
        status = 200 if ok else 503
        body = {"ok": ok, "database": "reachable" if ok else "unavailable"}
        request.app.state.readiness_cache = (monotonic(), status, body)
        return JSONResponse(status_code=status, content=body)
