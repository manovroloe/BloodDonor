"""Resolve per-application resources, making isolated tests possible."""
from typing import Annotated
from fastapi import Depends, Request
from ..repositories.supabase import SupabaseRepository

def get_repository(request: Request) -> SupabaseRepository:
    return request.app.state.repository

Repository = Annotated[SupabaseRepository, Depends(get_repository)]
