"""Same-origin request protection, safe caching, and privacy-conscious access logs."""
from __future__ import annotations
import logging
from time import perf_counter
from urllib.parse import quote, urlsplit
from uuid import uuid4
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, RedirectResponse
from .config import Settings

logger = logging.getLogger("bloodcare.access")
PROTECTED_ACCOUNT_PAGES = frozenset({
    "blood-search.html", "request-blood.html", "donor-registration.html", "appointment.html",
    "donations.html", "donation-records.html", "profile.html", "inventory.html", "requests.html", "user.html",
})

def _origin(value: str) -> tuple[str, str, int] | None:
    try:
        parsed = urlsplit(value)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
            return None
        return parsed.scheme.lower(), parsed.hostname.lower(), parsed.port or (443 if parsed.scheme == "https" else 80)
    except ValueError:
        return None

def allowed_write(request: Request, settings: Settings) -> bool:
    expected = _origin(settings.public_origin or str(request.base_url))
    origin = request.headers.get("origin")
    if origin is not None:
        return _origin(origin) == expected and expected is not None
    referer = request.headers.get("referer")
    if referer:
        return _origin(referer) == expected and expected is not None
    if request.headers.get("sec-fetch-site") in {"cross-site", "same-site"}:
        return False
    # Same-origin JS adds a custom header. Cross-origin websites cannot attach it
    # without a CORS preflight, and this application never enables cross-origin CORS.
    return request.headers.get("x-bloodcare-request") == "1"

def install_middleware(app: FastAPI, settings: Settings) -> None:
    @app.middleware("http")
    async def website_boundary(request: Request, call_next):
        start = perf_counter()
        request_id = uuid4().hex
        request.state.request_id = request_id
        path = request.url.path
        filename = path.rstrip("/").rsplit("/", 1)[-1].lower()
        protected = filename in PROTECTED_ACCOUNT_PAGES or filename.startswith(("staff", "admin")) and filename.endswith(".html")
        unsafe = request.method not in {"GET", "HEAD", "OPTIONS"}
        response = None
        if (path.startswith("/api/") or path == "/logout") and unsafe and not allowed_write(request, settings):
            response = JSONResponse(status_code=403, content={"detail": "This request must originate from the BloodCare website."})
        elif path == "/logout" and request.method == "GET" and (request.headers.get("sec-fetch-site") in {"cross-site", "same-site"} or request.headers.get("origin") and not allowed_write(request, settings)):
            response = JSONResponse(status_code=403, content={"detail": "Open BloodCare to sign out."})
        elif protected and not (request.cookies.get("bc_access_token") or request.cookies.get("bc_refresh_token")):
            target = path + ("?" + request.url.query if request.url.query else "")
            response = RedirectResponse("/login.html?next=" + quote(target, safe=""), status_code=303)
        if response is None:
            response = await call_next(request)
        if path.startswith("/api/") and not path.startswith("/api/storage/public/") or path == "/logout" or protected:
            response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
            response.headers["Pragma"] = "no-cache"
        elif filename.endswith((".html", ".js", ".css")) or path == "/":
            response.headers["Cache-Control"] = "no-cache, must-revalidate"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Content-Security-Policy"] = "base-uri 'self'; object-src 'none'; frame-ancestors 'none'"
        response.headers["X-Request-ID"] = request_id
        if settings.production:
            response.headers["Strict-Transport-Security"] = "max-age=31536000"
        # Log path only: URLs can contain names, email addresses, and tracking codes.
        logger.info("%s %s status=%s elapsed_ms=%.1f request_id=%s", request.method, path, response.status_code, (perf_counter() - start) * 1000, request_id)
        return response
