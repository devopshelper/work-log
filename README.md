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
- **Runs as a real service.** `install.sh` installs it as a hardened systemd
  unit with its own user, sandboxing and a health check.
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

## Install as a permanent service (Linux + systemd)

One command, from a checkout or straight from the internet:

```bash
# from the repo
sudo ./install.sh

# or without cloning
curl -fsSL https://raw.githubusercontent.com/devopshelper/work-log/main/install.sh | sudo bash
```

The installer is idempotent: running it again upgrades the code in place and
restarts the service. It:

1. installs `python3`/`venv`/`curl` if your distro is missing them
   (apt, dnf, yum, zypper, pacman and apk are supported);
2. creates a dedicated system user (default `work-log`, no shell, no home);
3. copies the app to `/opt/work-log` and builds a virtualenv there;
4. writes config to `/etc/work-log/work-log.env` and the database location to
   `/var/lib/work-log` (the only directory the service can write to);
5. installs `/etc/systemd/system/work-log.service` — `ProtectSystem=strict`,
   `NoNewPrivileges`, `ProtectHome`, a `@system-service` syscall filter, empty
   capability set, `Restart=on-failure` and `UMask=0077`;
6. enables and starts it, then waits for `/healthz` and prints diagnostics if
   the service does not come up.

### Options

| Flag | Default | Meaning |
| ---- | ------- | ------- |
| `--port` | `8000` | Port uvicorn listens on |
| `--host` | `127.0.0.1` | Bind address; `0.0.0.0` exposes it directly |
| `--user` | `work-log` | System user that runs the service |
| `--app-dir` | `/opt/work-log` | Where the code + virtualenv live |
| `--data-dir` | `/var/lib/work-log` | Where the SQLite database lives |
| `--conf-dir` | `/etc/work-log` | Where the env file lives |
| `--workers` | `1` | Uvicorn workers (SQLite is single-writer) |
| `--upgrade` | – | Refresh the code of an existing install, keep config |
| `--no-systemd` | – | Install files only (containers, runit, s6…) |
| `--uninstall` | – | Stop + remove the unit and code, keep the database |
| `--uninstall --purge` | – | Also delete the database, config and user |
| `--dry-run` | – | Print every action without changing anything |

### Managing the service

```bash
systemctl status work-log
systemctl restart work-log
journalctl -u work-log -f

sudo ./install.sh --upgrade       # after pulling new code
sudo ./install.sh --uninstall     # keeps /var/lib/work-log/work_log.db
sudo ./install.sh --uninstall --purge
```

### Behind a reverse proxy

The service listens on `127.0.0.1:8000` and trusts `X-Forwarded-*` from
localhost only.

```nginx
server {
    listen 80;
    server_name worklog.example.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Caddy is a one-liner: `worklog.example.com { reverse_proxy 127.0.0.1:8000 }`.

### Troubleshooting

```bash
journalctl -u work-log -n 50 --no-pager   # service log
sudo -u work-log /opt/work-log/bin/serve  # run in the foreground
curl -s http://127.0.0.1:8000/healthz     # health probe
```

Common causes: the port is already in use (`ss -ltnp | grep 8000`), or on
SELinux systems the database lives outside the allowed paths
(`sudo semanage fcontext -a -t httpd_sys_rw_content_t '/var/lib/work-log(/.*)?'`).

## Project layout

```text
work-log/
├── app/
│   ├── __init__.py
│   ├── main.py        # FastAPI app, routes, view models
│   ├── database.py    # SQLite engine + session factory
│   ├── models.py      # WorkLog model
│   └── dates.py       # Gregorian <-> Jalali conversion helpers
├── deploy/
│   ├── serve.sh           # launcher used by the unit (reads env, execs uvicorn)
│   ├── work-log.service.in # systemd unit template
│   └── work-log.env.example
├── templates/
│   └── index.html     # single page, RTL dashboard
├── static/
│   ├── css/style.css
│   └── js/app.js      # live two-way date syncing
├── tests/
│   └── test_dates.py
├── install.sh         # installer / upgrader / uninstaller
├── uninstall.sh
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

- [x] systemd service + one-command Linux installer
- [ ] Monthly view with a Jalali calendar grid
- [ ] Markdown rendering for the notes field
- [ ] Weekly/monthly summary + hours per category chart
- [ ] Optional login for a shared instance
- [ ] CSV export and import

## License

MIT
