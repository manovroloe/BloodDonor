"""Translate validated query payloads to PostgREST parameters."""
from typing import Any
from ..schemas.database import DbRequest

def _pg_scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return str(value)


def _in_value(values: Any) -> str:
    if not isinstance(values, list):
        values = [values]
    parts: list[str] = []
    for value in values:
        raw = _pg_scalar(value)
        if any(ch in raw for ch in [",", "(", ")", '"']):
            raw = '"' + raw.replace('"', '\\"') + '"'
        parts.append(raw)
    return "in.(" + ",".join(parts) + ")"


def build_params(body: DbRequest) -> list[tuple[str, str]]:
    params: list[tuple[str, str]] = [("select", body.select)] if body.action == "select" else []
    for f in body.filters:
        if f.op == "in":
            value = _in_value(f.value)
        elif f.op == "not":
            operator = f.operator or "eq"
            value = f"not.{operator}.{_pg_scalar(f.value)}"
        else:
            value = f"{f.op}.{_pg_scalar(f.value)}"
        params.append((f.column, value))
    if body.orders:
        order = ",".join(f"{o.column}.{'asc' if o.ascending else 'desc'}" for o in body.orders)
        params.append(("order", order))
    if body.range:
        params.append(("offset", str(body.range.start)))
        params.append(("limit", str(body.range.end - body.range.start + 1)))
    elif body.limit:
        params.append(("limit", str(body.limit)))
    return params
