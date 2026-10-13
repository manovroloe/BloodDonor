"""Public contact endpoint."""
from fastapi import APIRouter, Request
from ..core.security import token_from
from ..schemas.contacts import ContactPayload
from ..services.contacts import ContactService
from .dependencies import Repository
router = APIRouter(tags=["Contacts"])

@router.post("/api/contact")
async def submit_contact(body: ContactPayload, request: Request, repo: Repository):
    return await ContactService(repo).submit(body, token_from(request), request.url.path)
