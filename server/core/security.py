"""Browser session cookies are an HTTP concern, not database/business logic."""
from typing import Any
from fastapi import Request, Response
from .config import Settings

ACCESS_COOKIE = "bc_access_token"
REFRESH_COOKIE = "bc_refresh_token"

def token_from(request: Request) -> str | None:
    return request.cookies.get(ACCESS_COOKIE)

def set_auth_cookies(response: Response, payload: dict[str, Any], settings: Settings) -> None:
    for name, value, age in (
        (ACCESS_COOKIE, payload.get("access_token"), int(payload.get("expires_in") or 3600)),
        (REFRESH_COOKIE, payload.get("refresh_token"), 60 * 60 * 24 * 30),
    ):
        if value:
            response.set_cookie(name, value, httponly=True, secure=settings.cookie_secure, samesite="lax", max_age=age, path="/")

def clear_auth_cookies(response: Response, settings: Settings) -> None:
    for name in (ACCESS_COOKIE, REFRESH_COOKIE):
        response.delete_cookie(name, path="/", secure=settings.cookie_secure, httponly=True, samesite="lax")
