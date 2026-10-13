"""Validated auth API payloads."""
from __future__ import annotations

from pydantic import BaseModel


class AuthCredentials(BaseModel):
    email: str
    password: str


class SignUpPayload(AuthCredentials):
    full_name: str = ""
