"""HTTP authentication endpoints; cookie handling lives at this boundary."""
from fastapi import APIRouter, Request, Response, HTTPException
from fastapi.responses import JSONResponse, RedirectResponse
from ..core.security import clear_auth_cookies, set_auth_cookies, token_from, REFRESH_COOKIE
from ..schemas.auth import AuthCredentials, SignUpPayload
from ..services.auth import AuthService
from .dependencies import Repository

router = APIRouter(tags=["Authentication"])

@router.post("/api/auth/sign-in")
async def sign_in(credentials: AuthCredentials, response: Response, repo: Repository):
    try:
        payload = await AuthService(repo).sign_in(credentials)
    except HTTPException as exc:
        if exc.status_code != 403:
            raise
        denied = JSONResponse(status_code=403, content={"detail": exc.detail})
        clear_auth_cookies(denied, repo.settings)
        return denied
    set_auth_cookies(response, payload, repo.settings)
    return {"user": payload.get("user")}

@router.post("/api/auth/sign-up")
async def sign_up(credentials: SignUpPayload, response: Response, repo: Repository):
    payload = await AuthService(repo).sign_up(credentials)
    set_auth_cookies(response, payload, repo.settings)
    return {"user": payload.get("user"), "session": bool(payload.get("access_token"))}

@router.post("/api/auth/refresh")
async def refresh_session(request: Request, response: Response, repo: Repository):
    try:
        payload = await AuthService(repo).refresh(request.cookies.get(REFRESH_COOKIE))
    except HTTPException as exc:
        if exc.status_code != 401:
            raise
        expired = JSONResponse(status_code=401, content={"detail": exc.detail})
        clear_auth_cookies(expired, repo.settings)
        return expired
    set_auth_cookies(response, payload, repo.settings)
    return {"user": payload.get("user")}

@router.get("/api/auth/session")
async def auth_session(request: Request, repo: Repository):
    return {"user": await AuthService(repo).user(token_from(request))}

@router.post("/api/auth/sign-out")
async def sign_out(request: Request, response: Response, repo: Repository):
    await AuthService(repo).revoke(token_from(request))
    clear_auth_cookies(response, repo.settings)
    return {"ok": True}

def logout_response(repo: Repository) -> RedirectResponse:
    response = RedirectResponse("/login.html?logged_out=1", status_code=303)
    clear_auth_cookies(response, repo.settings)
    response.headers["Cache-Control"] = "no-store"
    return response

@router.get("/logout")
async def logout_link_get(repo: Repository):
    """Legacy direct-navigation fallback; cross-site navigation is blocked by middleware."""
    return logout_response(repo)

@router.post("/logout")
async def logout_link_post(repo: Repository):
    """Native form fallback: local logout must not depend on an upstream service."""
    return logout_response(repo)
