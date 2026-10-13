"""Admin-only endpoints; authorization is checked by every service workflow."""
from uuid import UUID
from fastapi import APIRouter, Request
from ..core.security import token_from
from ..schemas.admin import AdminStaffCreatePayload, AdminStaffPasswordPayload
from ..schemas.contacts import ContactReplyPayload
from ..services.admin import AdminService
from .dependencies import Repository
router = APIRouter(tags=["Administration"])

@router.get("/api/admin/config")
async def admin_config(request: Request, repo: Repository):
    return await AdminService(repo).config(token_from(request))

@router.post("/api/admin/staff")
async def admin_create_staff(body: AdminStaffCreatePayload, request: Request, repo: Repository):
    return await AdminService(repo).create_staff(body, token_from(request))

@router.post("/api/admin/staff/{staff_id}/password")
async def admin_reset_staff_password(staff_id: UUID, body: AdminStaffPasswordPayload, request: Request, repo: Repository):
    return await AdminService(repo).reset_password(str(staff_id), body, token_from(request))

@router.post("/api/admin/contact/{contact_id}/reply")
async def admin_reply_contact(contact_id: UUID, body: ContactReplyPayload, request: Request, repo: Repository):
    return await AdminService(repo).reply(str(contact_id), body, token_from(request))
