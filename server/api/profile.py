"""Download the existing BloodCare profile PDF."""
from fastapi import APIRouter, Request, Response
from ..core.security import set_auth_cookies, token_from, REFRESH_COOKIE
from ..services.profile import ProfileService
from .dependencies import Repository
router = APIRouter(tags=["Profile"])

@router.get("/api/profile/ticket.pdf")
async def profile_ticket_pdf(request: Request, repo: Repository):
    ticket = await ProfileService(repo).ticket(token_from(request), request.cookies.get(REFRESH_COOKIE))
    response = Response(ticket.content, media_type="application/pdf", headers={"Content-Disposition": f'attachment; filename="{ticket.filename}"', "Cache-Control": "no-store"})
    if ticket.refreshed_auth:
        set_auth_cookies(response, ticket.refreshed_auth, repo.settings)
    return response
