"""Validated admin API payloads."""
from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, Field


class AdminStaffCreatePayload(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)
    confirm_password: str = Field(min_length=8, max_length=128)
    role: Literal["staff", "admin"] = "staff"
    primary_facility_id: str = Field(min_length=36, max_length=36)


class AdminStaffPasswordPayload(BaseModel):
    password: str = Field(min_length=8, max_length=128)
    confirm_password: str = Field(min_length=8, max_length=128)
