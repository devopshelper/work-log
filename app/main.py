"""FastAPI application: daily work journal with Jalali + Gregorian dates."""

from __future__ import annotations

import datetime as dt
from typing import Optional

from fastapi import Depends, FastAPI, Form, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from . import dates
from .database import BASE_DIR, get_db, init_db
from .models import WorkLog

CATEGORIES = [
    "توسعه نرم‌افزار",
    "طراحی",
    "جلسه و هماهنگی",
    "رفع باگ",
    "تحقیق و یادگیری",
    "مستندسازی",
    "پشتیبانی",
    "سایر",
]

app = FastAPI(title="Work Log · گزارش کار روزانه", version="0.1.0")

app.mount("/static", StaticFiles(directory=str(BASE_DIR / "static")), name="static")
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

init_db()


def _parse_date(raw: Optional[str]) -> Optional[dt.date]:
    if not raw:
        return None
    try:
        return dt.date.fromisoformat(raw.strip())
    except ValueError:
        return None


def _stats(db: Session) -> dict:
    total_days = db.query(func.count(WorkLog.id)).scalar() or 0
    total_hours = db.query(func.coalesce(func.sum(WorkLog.hours), 0.0)).scalar() or 0.0

    logged = {day for (day,) in db.query(WorkLog.log_date).all()}
    streak = 0
    day = dt.date.today()
    while day.isoformat() in logged:
        streak += 1
        day -= dt.timedelta(days=1)

    return {
        "total_days": total_days,
        "total_hours": round(float(total_hours), 1),
        "streak": streak,
    }


def _entry(row: WorkLog) -> dict:
    try:
        info = dates.describe(dt.date.fromisoformat(row.log_date))
    except ValueError:  # pragma: no cover - defensive
        info = {
            "gregorian": row.log_date,
            "jalali": row.jalali_date,
            "jalali_short": row.jalali_date,
            "jalali_long": row.jalali_date,
            "month_fa": "",
            "weekday_fa": "",
        }
    return {
        "id": row.id,
        "title": row.title,
        "category": row.category,
        "details": row.details,
        "hours": row.hours,
        "tags": row.tag_list(),
        **info,
    }


@app.get("/", response_class=HTMLResponse)
def index(
    request: Request,
    d: Optional[str] = Query(None, description="ISO date to open"),
    q: Optional[str] = Query(None, description="search text"),
    cat: Optional[str] = Query(None, description="category filter"),
    db: Session = Depends(get_db),
):
    selected = _parse_date(d) or dt.date.today()
    existing = (
        db.query(WorkLog).filter(WorkLog.log_date == selected.isoformat()).first()
    )

    query = db.query(WorkLog)
    if q and q.strip():
        like = f"%{q.strip()}%"
        query = query.filter(
            or_(
                WorkLog.title.ilike(like),
                WorkLog.details.ilike(like),
                WorkLog.tags.ilike(like),
            )
        )
    if cat:
        query = query.filter(WorkLog.category == cat)

    rows = query.order_by(WorkLog.log_date.desc()).all()

    form = {
        "title": existing.title if existing else "",
        "category": existing.category if existing else CATEGORIES[0],
        "details": existing.details if existing else "",
        "hours": ""
        if not existing or existing.hours is None
        else f"{existing.hours:g}",
        "tags": existing.tags if existing else "",
    }

    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={
            "today": dates.describe(dt.date.today()),
            "selected": dates.describe(selected),
            "form": form,
            "editing": existing is not None,
            "logs": [_entry(row) for row in rows],
            "categories": CATEGORIES,
            "stats": _stats(db),
            "q": q or "",
            "cat": cat or "",
        },
    )


@app.post("/logs")
def save_log(
    log_date: str = Form(...),
    jalali: str = Form(""),
    title: str = Form(...),
    category: str = Form(CATEGORIES[0]),
    details: str = Form(""),
    hours: str = Form(""),
    tags: str = Form(""),
    db: Session = Depends(get_db),
):
    """Create or update the entry of a single day."""
    day = _parse_date(log_date)
    if day is None and jalali.strip():
        day = dates.parse_jalali(jalali)
    if day is None:
        day = dt.date.today()

    hours_value: Optional[float] = None
    cleaned = hours.strip().replace("٫", ".").replace(",", ".")
    if cleaned:
        try:
            hours_value = float(cleaned)
        except ValueError:
            hours_value = None

    payload = {
        "log_date": day.isoformat(),
        "jalali_date": dates.jalali_string(day),
        "title": title.strip()[:200] or "بدون عنوان",
        "category": category,
        "details": details.strip(),
        "hours": hours_value,
        "tags": ",".join(t.strip() for t in tags.split(",") if t.strip())[:200],
    }

    row = db.query(WorkLog).filter(WorkLog.log_date == day.isoformat()).first()
    if row is None:
        db.add(WorkLog(**payload))
    else:
        for key, value in payload.items():
            setattr(row, key, value)

    db.commit()
    return RedirectResponse(url=f"/?d={day.isoformat()}", status_code=303)


@app.post("/logs/{log_id}/delete")
def delete_log(log_id: int, db: Session = Depends(get_db)):
    row = db.get(WorkLog, log_id)
    if row is not None:
        db.delete(row)
        db.commit()
    return RedirectResponse(url="/", status_code=303)


@app.get("/api/dates/convert")
def convert_date(gregorian: Optional[str] = None, jalali: Optional[str] = None):
    """Convert between the two calendars; used by the live form preview."""
    try:
        if gregorian:
            day = _parse_date(gregorian)
            if day is None:
                return JSONResponse({"ok": False, "error": "invalid date"}, 400)
        elif jalali:
            day = dates.parse_jalali(jalali)
        else:
            return JSONResponse({"ok": False, "error": "no date given"}, 400)
    except ValueError as exc:
        return JSONResponse({"ok": False, "error": str(exc)}, 400)

    return {"ok": True, **dates.describe(day)}


@app.get("/export.json")
def export_json(db: Session = Depends(get_db)):
    """Download every entry as JSON (lightweight backup)."""
    rows = db.query(WorkLog).order_by(WorkLog.log_date).all()
    payload = [
        {
            "date": row.log_date,
            "jalali_date": row.jalali_date,
            "title": row.title,
            "category": row.category,
            "details": row.details,
            "hours": row.hours,
            "tags": row.tag_list(),
        }
        for row in rows
    ]
    return JSONResponse(
        payload,
        headers={"Content-Disposition": 'attachment; filename="work-log.json"'},
    )


@app.get("/healthz")
def healthz():
    return {"status": "ok"}
