# Work Log · گزارش کار روزانه

A tiny, self-hosted daily work journal. Every day you write down what you did,
and the entry is stored in SQLite with **both** the Gregorian and the Persian
(Jalali) date. The UI is fully **RTL** and designed for Persian first.

![Python](https://img.shields.io/badge/python-3.10%2B-blue)
![FastAPI](https://img.shields.io/badge/FastAPI-0.110%2B-009688)
![SQLite](https://img.shields.io/badge/SQLite-3-003B57)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Dual calendar, always.** Each entry stores an ISO date and its Jalali
  counterpart. Pick a day in either calendar — the other one updates live.
- **One entry per day.** Saving the same day twice updates it instead of
  creating a duplicate, so the log reads like a journal, not a feed.
- **Categories, hours and tags** for filtering and quick summaries.
- **Search + filters** across titles, notes and tags.
- **Small dashboard**: number of logged days, total hours, and the current
  consecutive-day streak.
- **JSON export** at `/export.json` for backups.
- **No calendar dependency**: the Jalali conversion is a compact pure-Python
  port of the well-known jalaali algorithm (verified against .NET
  `PersianCalendar`).

## Quick start

```bash
git clone https://github.com/<you>/work-log.git
cd work-log

python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate    # macOS / Linux

pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open <http://127.0.0.1:8000>. The SQLite file (`work_log.db`) is created on
first run and is ignored by git.

## Project layout

```text
work-log/
├── app/
│   ├── __init__.py
│   ├── main.py        # FastAPI app, routes, view models
│   ├── database.py    # SQLite engine + session factory
│   ├── models.py      # WorkLog model
│   └── dates.py       # Gregorian <-> Jalali conversion helpers
├── templates/
│   └── index.html     # single page, RTL dashboard
├── static/
│   ├── css/style.css
│   └── js/app.js      # live two-way date syncing
├── requirements.txt
└── README.md
```

## HTTP API

| Method | Path | Purpose |
| ------ | ---- | ------- |
| `GET`  | `/` | Dashboard; `?d=YYYY-MM-DD` opens a day, `?q=` and `?cat=` filter |
| `POST` | `/logs` | Create/update the entry of a day |
| `POST` | `/logs/{id}/delete` | Delete an entry |
| `GET`  | `/api/dates/convert` | `?gregorian=` or `?jalali=` → both calendars + Persian labels |
| `GET`  | `/export.json` | Download every entry as JSON |
| `GET`  | `/docs` | Interactive OpenAPI documentation |

## Configuration

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `WORK_LOG_DB` | `./work_log.db` | Path to the SQLite database file |

## Roadmap ideas

- [ ] Monthly view with a Jalali calendar grid
- [ ] Markdown rendering for the notes field
- [ ] Weekly/monthly summary + hours per category chart
- [ ] Optional login for a shared instance
- [ ] CSV export and import

## License

MIT
