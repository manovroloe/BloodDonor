"""Validated storage API payloads."""
from __future__ import annotations

from pydantic import BaseModel


class RemoveStoragePayload(BaseModel):
    paths: list[str]
