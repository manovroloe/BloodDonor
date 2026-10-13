"""Shared error formatting; API exceptions never expose runtime secrets."""
from typing import Any

def error_message(payload: Any, fallback: str) -> str:
    if isinstance(payload, dict):
        return str(payload.get("msg") or payload.get("message") or payload.get("error_description") or payload.get("error") or fallback)
    return str(payload or fallback)
