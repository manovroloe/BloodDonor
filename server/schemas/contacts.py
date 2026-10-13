"""Validated contacts API payloads."""
from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, Field


class ContactPayload(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=254)
    phone: str = Field(min_length=7, max_length=15)
    inquiry_type: Literal["general", "donation", "blood-request", "appointment", "facility", "technical", "other"] = "general"
    message: str = Field(min_length=10, max_length=3000)
    source_page: str = Field(default="", max_length=200)


class ContactReplyPayload(BaseModel):
    message: str = Field(min_length=2, max_length=5000)
