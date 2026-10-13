"""Validated database API payloads."""
from __future__ import annotations

from typing import Any, Literal
from pydantic import BaseModel, Field, model_validator


class FilterSpec(BaseModel):
    op: Literal["eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike", "is", "in", "not"]
    column: str = Field(min_length=1, max_length=100)
    value: Any = None
    operator: str | None = None


class OrderSpec(BaseModel):
    column: str = Field(min_length=1, max_length=100)
    ascending: bool = True


class RangeSpec(BaseModel):
    start: int = Field(ge=0)
    end: int = Field(ge=0)

    @model_validator(mode="after")
    def validate_bounds(self) -> "RangeSpec":
        if self.end < self.start:
            raise ValueError("Range end must be greater than or equal to start.")
        if self.end - self.start + 1 > 5000:
            raise ValueError("A range cannot exceed 5000 records.")
        return self


class DbRequest(BaseModel):
    table: str
    action: Literal["select", "insert", "update", "delete"] = "select"
    select: str = "*"
    filters: list[FilterSpec] = Field(default_factory=list)
    orders: list[OrderSpec] = Field(default_factory=list)
    limit: int | None = Field(default=None, ge=1, le=5000)
    range: RangeSpec | None = None
    single: bool = False
    maybe_single: bool = False
    count: Literal["exact"] | None = None
    head: bool = False
    data: Any = None
