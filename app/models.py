"""SQLAlchemy models."""

from __future__ import annotations

import datetime as dt

from sqlalchemy import DateTime, Float, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class WorkLog(Base):
    """One entry per calendar day (upserted when a day is saved twice)."""

    __tablename__ = "work_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    log_date: Mapped[str] = mapped_column(String(10), unique=True, index=True)
    jalali_date: Mapped[str] = mapped_column(String(10), index=True)
    title: Mapped[str] = mapped_column(String(200))
    category: Mapped[str] = mapped_column(String(60), default="توسعه", index=True)
    details: Mapped[str] = mapped_column(Text, default="")
    hours: Mapped[float | None] = mapped_column(Float, nullable=True)
    tags: Mapped[str] = mapped_column(String(200), default="")
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime, default=dt.datetime.utcnow
    )
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime, default=dt.datetime.utcnow, onupdate=dt.datetime.utcnow
    )

    def tag_list(self) -> list[str]:
        return [t.strip() for t in (self.tags or "").split(",") if t.strip()]

    def __repr__(self) -> str:  # pragma: no cover - debugging helper
        return f"<WorkLog {self.log_date} {self.title!r}>"
