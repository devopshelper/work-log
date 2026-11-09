#!/usr/bin/env bash
# Work Log launcher.
#
# Reads its configuration from the environment (usually provided by
# /etc/work-log/work-log.env via systemd's EnvironmentFile=) and execs uvicorn.
# It is intentionally tiny so the unit file stays readable and testable.
set -euo pipefail

_BIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
APP_DIR="${WORK_LOG_APP_DIR:-$(cd -- "$_BIN_DIR/.." && pwd)}"

cd "$APP_DIR"

: "${WORK_LOG_HOST:=127.0.0.1}"
: "${WORK_LOG_PORT:=8000}"
: "${WORK_LOG_WORKERS:=1}"
: "${WORK_LOG_FORWARDED_IPS:=127.0.0.1}"
: "${WORK_LOG_LOG_LEVEL:=info}"

PYTHON="$APP_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  echo "work-log: virtualenv not found at $PYTHON" >&2
  echo "work-log: run install.sh again, or create it with 'python3 -m venv .venv'" >&2
  exit 78
fi

exec "$PYTHON" -m uvicorn app.main:app \
  --host "$WORK_LOG_HOST" \
  --port "$WORK_LOG_PORT" \
  --workers "$WORK_LOG_WORKERS" \
  --proxy-headers \
  --forwarded-allow-ips "$WORK_LOG_FORWARDED_IPS" \
  --no-server-header \
  --log-level "$WORK_LOG_LOG_LEVEL"
