"""Application composition only. Start with python run.py or the supplied scripts."""
from __future__ import annotations
import asyncio
import logging
from contextlib import asynccontextmanager
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware
from . import __version__
from .api import admin, auth, contacts, database, health, profile, storage
from .core.config import Settings
from .core.middleware import install_middleware
from .repositories.supabase import SupabaseRepository

logger = logging.getLogger("bloodcare")

def create_app(settings: Settings | None = None, *, transport: httpx.AsyncBaseTransport | None = None) -> FastAPI:
    config = settings or Settings.from_env()
    config.validate()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        async with httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=10.0), limits=httpx.Limits(max_connections=50, max_keepalive_connections=20), transport=transport, follow_redirects=False) as http:
            app.state.settings = config
            app.state.repository = SupabaseRepository(http, config)
            app.state.readiness_lock = asyncio.Lock()
            app.state.readiness_cache = None
            if not config.configured:
                logger.warning("Supabase is not configured. Public pages can load, but live data needs server configuration.")
            yield

    app = FastAPI(title="BloodCare API", version=__version__, lifespan=lifespan, docs_url=None if config.production else "/docs", redoc_url=None if config.production else "/redoc", openapi_url=None if config.production else "/openapi.json")
    app.state.settings = config
    install_middleware(app, config)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=config.trusted_hosts)

    @app.exception_handler(httpx.RequestError)
    async def upstream_error(request: Request, exc: httpx.RequestError):
        rid = getattr(request.state, "request_id", "unknown")
        logger.warning("Supabase network error (%s), request_id=%s", type(exc).__name__, rid)
        return JSONResponse(status_code=503, content={"detail": "BloodCare is temporarily unable to reach its data service. Please try again shortly.", "request_id": rid})

    @app.exception_handler(Exception)
    async def unexpected_error(request: Request, exc: Exception):
        rid = getattr(request.state, "request_id", "unknown")
        logger.error("Unexpected server error (%s), request_id=%s", type(exc).__name__, rid)
        return JSONResponse(status_code=500, content={"detail": "BloodCare could not complete this request. Please try again.", "request_id": rid}, headers={"Cache-Control": "no-store"})

    for router in (health.router, auth.router, database.router, contacts.router, admin.router, profile.router, storage.router):
        app.include_router(router)
    # Keep unknown API paths away from the static site.
    @app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"], include_in_schema=False)
    async def unknown_api(path: str):
        return JSONResponse(status_code=404, content={"detail": "Unknown BloodCare API route."})
    app.mount("/", StaticFiles(directory=config.client_dir, html=True, follow_symlink=False), name="client")
    return app

app = create_app()
