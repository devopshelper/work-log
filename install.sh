#!/usr/bin/env bash
#
# Work Log installer - sets the app up as a permanent systemd service.
#
#   curl -fsSL https://raw.githubusercontent.com/devopshelper/work-log/main/install.sh | sudo bash
#   sudo ./install.sh --port 8000 --host 127.0.0.1
#   sudo ./install.sh --upgrade
#   sudo ./install.sh --uninstall [--purge]
#
# Design goals: idempotent, no dependencies beyond python3 + a package
# manager, everything the service owns lives in three directories.
set -euo pipefail

REPO_SLUG="devopshelper/work-log"
REPO_REF="main"
SERVICE_NAME="work-log"

APP_DIR="/opt/work-log"
DATA_DIR="/var/lib/work-log"
CONF_DIR="/etc/work-log"
RUN_USER="work-log"
HOST="127.0.0.1"
PORT="8000"
WORKERS="1"

MODE="install"        # install | upgrade | uninstall
PURGE=0
FORCE=0
NO_SYSTEMD=0
DRY_RUN=0
SCRIPT_DIR=""
SOURCE_DIR=""
DOWNLOAD_DIR=""

# ---------------------------------------------------------------- utilities
if [[ -t 1 ]] && [[ -t 2 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serr %s%s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
step() { printf '  o %s\n' "$*"; }

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  + %s\n' "$*"
  else
    "$@"
  fi
}

usage() {
  cat <<'USAGE'
Work Log installer

Usage:
  sudo ./install.sh [options]
  sudo ./install.sh --upgrade
  sudo ./install.sh --uninstall [--purge]

Options:
  --port PORT          Port to listen on (default 8000)
  --host ADDRESS       Bind address (default 127.0.0.1). Use 0.0.0.0 to expose
                       the app directly, or keep loopback behind a proxy.
  --user NAME          System user that runs the service (default work-log)
  --app-dir DIR        Where the code is installed (default /opt/work-log)
  --data-dir DIR       Where the SQLite database lives (default /var/lib/work-log)
  --conf-dir DIR       Where the env file lives (default /etc/work-log)
  --workers N          Uvicorn workers (default 1; SQLite is single-writer)
  --no-systemd         Copy files and build the virtualenv, skip the unit
  --upgrade            Refresh the code of an existing install and restart it
  --uninstall          Stop and remove the service (keeps the database)
  --purge              With --uninstall: also delete database, config and user
  --force              Overwrite an existing config file
  --dry-run            Print what would happen, change nothing
  -h, --help           Show this help

Files after installation:
  /opt/work-log                  code + virtualenv (root owned, read-only to user)
  /var/lib/work-log/work_log.db  database          (writable by the service user)
  /etc/work-log/work-log.env     configuration     (root:work-log 0640)
  /etc/systemd/system/work-log.service

Service management:
  systemctl status work-log
  systemctl restart work-log
  journalctl -u work-log -f
USAGE
}

cleanup() {
  if [[ -n "$DOWNLOAD_DIR" && -d "$DOWNLOAD_DIR" ]]; then
    rm -rf "$DOWNLOAD_DIR"
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------- arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)        PORT="${2:?--port needs a value}"; shift 2 ;;
    --host)        HOST="${2:?--host needs a value}"; shift 2 ;;
    --user)        RUN_USER="${2:?--user needs a value}"; shift 2 ;;
    --workers)     WORKERS="${2:?--workers needs a value}"; shift 2 ;;
    --app-dir)     APP_DIR="${2:?--app-dir needs a value}"; shift 2 ;;
    --data-dir)    DATA_DIR="${2:?--data-dir needs a value}"; shift 2 ;;
    --conf-dir)    CONF_DIR="${2:?--conf-dir needs a value}"; shift 2 ;;
    --upgrade)     MODE="upgrade"; shift ;;
    --uninstall)   MODE="uninstall"; shift ;;
    --purge)       PURGE=1; shift ;;
    --no-systemd)  NO_SYSTEMD=1; shift ;;
    --force)       FORCE=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown option: $1 (try --help)" ;;
  esac
done

ENV_FILE="$CONF_DIR/work-log.env"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# ------------------------------------------------------------- validation
[[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be a number"
(( PORT >= 1 && PORT <= 65535 )) || die "--port must be between 1 and 65535"
[[ "$WORKERS" =~ ^[0-9]+$ ]] || die "--workers must be a number"
(( WORKERS >= 1 && WORKERS <= 16 )) || die "--workers must be between 1 and 16"
[[ "$RUN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "--user is not a valid unix user name"
[[ "$APP_DIR" = /* ]] || die "--app-dir must be an absolute path"
[[ "$DATA_DIR" = /* ]] || die "--data-dir must be an absolute path"
[[ "$CONF_DIR" = /* ]] || die "--conf-dir must be an absolute path"

guard_path() {
  case "$1" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      die "refusing to use $1 as an install path (pick a dedicated directory)" ;;
  esac
}
guard_path "$APP_DIR"
guard_path "$DATA_DIR"
guard_path "$CONF_DIR"

if [[ $DRY_RUN -eq 0 ]] && [[ $(uname -s) != "Linux" ]]; then
  die "this installer only supports Linux (uname -s = $(uname -s)); use --dry-run to preview"
fi

if [[ ${EUID:-0} -ne 0 && $DRY_RUN -eq 0 ]]; then
  die "please run as root: sudo bash $0"
fi

# --------------------------------------------------------- source discovery
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
if [[ -f "$SCRIPT_DIR/app/main.py" && -f "$SCRIPT_DIR/deploy/work-log.service.in" ]]; then
  SOURCE_DIR="$SCRIPT_DIR"
fi

fetch_source() {
  [[ -n "$SOURCE_DIR" ]] && return 0
  log "Downloading $REPO_SLUG@$REPO_REF"
  DOWNLOAD_DIR="$(mktemp -d)"
  local tarball="$DOWNLOAD_DIR/source.tar.gz"
  local url="https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REPO_REF"

  if command -v curl >/dev/null 2>&1; then
    run curl -fsSL "$url" -o "$tarball"
  elif command -v wget >/dev/null 2>&1; then
    run wget -qO "$tarball" "$url"
  else
    die "need curl or wget to download the sources"
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    SOURCE_DIR="$DOWNLOAD_DIR/work-log-$REPO_REF"
    return 0
  fi
  tar -xzf "$tarball" -C "$DOWNLOAD_DIR"
  SOURCE_DIR="$DOWNLOAD_DIR/work-log-$REPO_REF"
  [[ -f "$SOURCE_DIR/app/main.py" ]] || die "the downloaded archive looks wrong (no app/main.py)"
}

# ------------------------------------------------------------ dependencies
install_pkg() {
  local pkgs="$*"
  step "installing packages: $pkgs"
  if   command -v apt-get >/dev/null 2>&1; then run apt-get update -qq && run apt-get install -y -qq $pkgs
  elif command -v dnf     >/dev/null 2>&1; then run dnf install -y -q $pkgs
  elif command -v yum     >/dev/null 2>&1; then run yum install -y -q $pkgs
  elif command -v zypper  >/dev/null 2>&1; then run zypper --non-interactive install -y $pkgs
  elif command -v pacman  >/dev/null 2>&1; then run pacman -Sy --needed --noconfirm $pkgs
  elif command -v apk     >/dev/null 2>&1; then run apk add --no-cache $pkgs
  else die "no supported package manager found (apt/dnf/yum/zypper/pacman/apk)"
  fi
}

ensure_base_packages() {
  local missing=0
  command -v python3 >/dev/null 2>&1 || missing=1
  command -v curl    >/dev/null 2>&1 || missing=1
  [[ $missing -eq 0 ]] && return 0

  if command -v apt-get >/dev/null 2>&1; then
    install_pkg python3 python3-venv curl ca-certificates
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    install_pkg python3 python3-pip curl
  elif command -v zypper >/dev/null 2>&1; then
    install_pkg python3 python3-pip python3-virtualenv curl
  elif command -v pacman >/dev/null 2>&1; then
    install_pkg python curl
  elif command -v apk >/dev/null 2>&1; then
    install_pkg python3 py3-pip curl
  fi
}

ensure_user() {
  if id -u "$RUN_USER" >/dev/null 2>&1; then
    step "user $RUN_USER already exists"
    return 0
  fi
  step "creating system user $RUN_USER"
  if command -v useradd >/dev/null 2>&1; then
    if ! id -g "$RUN_USER" >/dev/null 2>&1; then
      run groupadd --system "$RUN_USER" || run groupadd "$RUN_USER"
    fi
    run useradd --system --gid "$RUN_USER" --home-dir "$DATA_DIR" \
      --no-create-home --shell /usr/sbin/nologin "$RUN_USER"
  else
    run adduser -S -D -H -s /sbin/nologin -h "$DATA_DIR" "$RUN_USER"
  fi
}

# ------------------------------------------------------------------ install
do_install() {
  log "Installing Work Log into $APP_DIR (service user: $RUN_USER)"

  ensure_base_packages
  ensure_user

  step "creating directories"
  run mkdir -p "$APP_DIR" "$DATA_DIR" "$CONF_DIR"

  step "copying application files"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  + tar -C %s -cf - . | tar -C %s -xf -\n' "$SOURCE_DIR" "$APP_DIR"
  else
    tar -C "$SOURCE_DIR" \
      --exclude='./.git' --exclude='./.venv' --exclude='./venv' \
      --exclude='./__pycache__' --exclude='*/__pycache__' \
      --exclude='./.pytest_cache' --exclude='*.pyc' \
      --exclude='./work_log.db' --exclude='./*.db-journal' \
      -cf - . | tar -C "$APP_DIR" -xf -
    mkdir -p "$APP_DIR/bin"
    install -m 0755 "$APP_DIR/deploy/serve.sh" "$APP_DIR/bin/serve"
  fi

  step "building the virtualenv"
  if [[ -x "$APP_DIR/.venv/bin/python" ]]; then
    step "reusing the existing virtualenv"
  else
    if ! run python3 -m venv "$APP_DIR/.venv"; then
      warn "venv creation failed; installing the distro venv package"
      if command -v apt-get >/dev/null 2>&1; then
        install_pkg python3-venv python3-pip
      elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        install_pkg python3-pip
      fi
      run python3 -m venv "$APP_DIR/.venv"
    fi
  fi

  step "installing python dependencies"
  run "$APP_DIR/.venv/bin/python" -m pip install --quiet --upgrade pip
  if ! run "$APP_DIR/.venv/bin/python" -m pip install --quiet -r "$APP_DIR/requirements.txt"; then
    die "pip install failed (very old distros may need gcc and python3-dev)"
  fi

  step "precompiling bytecode"
  run "$APP_DIR/.venv/bin/python" -m compileall -q "$APP_DIR/app"

  step "setting ownership and permissions"
  run chown -R root:root "$APP_DIR"
  run chmod 0755 "$APP_DIR"
  run chown -R "$RUN_USER:$RUN_USER" "$DATA_DIR"
  run chmod 0750 "$DATA_DIR"

  # ---- configuration file
  if [[ -f "$ENV_FILE" && $FORCE -eq 0 ]]; then
    step "keeping existing $ENV_FILE"
    if ! grep -q '^WORK_LOG_DB=' "$ENV_FILE"; then
      warn "$ENV_FILE has no WORK_LOG_DB; the database will sit next to the code"
    fi
  else
    step "writing $ENV_FILE"
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '  + write %s\n' "$ENV_FILE"
    else
      cat > "$ENV_FILE" <<ENVEOF
# Work Log configuration - edit, then: systemctl restart work-log
WORK_LOG_DB=$DATA_DIR/work_log.db
WORK_LOG_HOST=$HOST
WORK_LOG_PORT=$PORT
WORK_LOG_WORKERS=$WORKERS
WORK_LOG_FORWARDED_IPS=127.0.0.1
WORK_LOG_LOG_LEVEL=info
ENVEOF
      chown root:"$RUN_USER" "$ENV_FILE" 2>/dev/null || chown root "$ENV_FILE"
      chmod 0640 "$ENV_FILE"
    fi
  fi

  if [[ $NO_SYSTEMD -eq 1 ]]; then
    warn "--no-systemd given: no unit installed"
    finish_manual
    return 0
  fi

  # ---- systemd unit
  step "installing $UNIT_PATH"
  local protect_home="yes"
  case "$APP_DIR" in /home/*|/root/*) protect_home="no" ;; esac
  case "$DATA_DIR" in /home/*|/root/*) protect_home="no" ;; esac

  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  + render %s from %s/deploy/work-log.service.in\n' "$UNIT_PATH" "$SOURCE_DIR"
  else
    sed -e "s|@REPO_SLUG@|$REPO_SLUG|g" \
        -e "s|@APP_DIR@|$APP_DIR|g" \
        -e "s|@DATA_DIR@|$DATA_DIR|g" \
        -e "s|@ENV_FILE@|$ENV_FILE|g" \
        -e "s|@RUN_USER@|$RUN_USER|g" \
        -e "s|@PROTECT_HOME@|$protect_home|g" \
        "$SOURCE_DIR/deploy/work-log.service.in" > "$UNIT_PATH"
    chmod 0644 "$UNIT_PATH"
  fi

  if [[ $DRY_RUN -eq 0 ]] && ! command -v systemctl >/dev/null 2>&1; then
    warn "systemd not found (container?); the unit was written but not enabled"
    finish_manual
    return 0
  fi

  if [[ $DRY_RUN -eq 0 ]] && [[ ! -d /run/systemd/system ]]; then
    warn "systemd is not the running init (WSL1/container?); not enabling the unit"
    finish_manual
    return 0
  fi

  step "reloading systemd and (re)starting the service"
  run systemctl daemon-reload
  run systemctl enable "$SERVICE_NAME"
  run systemctl restart "$SERVICE_NAME"

  healthcheck
  finish_service
}

healthcheck() {
  [[ $DRY_RUN -eq 1 ]] && return 0
  local probe_host="$HOST"
  [[ "$probe_host" == "0.0.0.0" || "$probe_host" == "::" ]] && probe_host="127.0.0.1"
  local url="http://$probe_host:$PORT/healthz"

  step "waiting for $url"
  local i
  for i in $(seq 1 30); do
    if curl -fsS --max-time 2 "$url" 2>/dev/null | grep -q '"ok"'; then
      ok "service answered on $url"
      return 0
    fi
    sleep 1
  done

  warn "the service did not answer within 30s - diagnostics follow:"
  systemctl --no-pager --lines=20 status "$SERVICE_NAME" || true
  journalctl -u "$SERVICE_NAME" --no-pager --lines=40 2>/dev/null || true
  die "install finished but the service is not healthy"
}

finish_service() {
  local probe_host="$HOST"
  [[ "$probe_host" == "0.0.0.0" || "$probe_host" == "::" ]] && probe_host="127.0.0.1"
  printf '\n%s  Work Log is installed and running as a service.%s\n\n' "$C_GREEN" "$C_RESET"
  cat <<EOF
  URL          http://$probe_host:$PORT
  App          $APP_DIR
  Database     $DATA_DIR/work_log.db
  Config       $ENV_FILE
  Service      $UNIT_PATH

  systemctl status work-log
  systemctl restart work-log
  journalctl -u work-log -f
EOF
  if [[ "$HOST" != "127.0.0.1" && "$HOST" != "::1" ]]; then
    cat <<EOF

  Bind address is $HOST - open the firewall if needed:
    ufw allow $PORT/tcp                                         (ubuntu/debian)
    firewall-cmd --permanent --add-port=$PORT/tcp && firewall-cmd --reload   (rhel/fedora)
EOF
  else
    cat <<EOF

  Binds to localhost only. For remote access put nginx/caddy in front, or set
  WORK_LOG_HOST=0.0.0.0 in $ENV_FILE and restart the service.
EOF
  fi
}

finish_manual() {
  cat <<EOF

  Files are in place. Start the app manually with:

    sudo -u $RUN_USER env WORK_LOG_DB=$DATA_DIR/work_log.db \
      WORK_LOG_HOST=$HOST WORK_LOG_PORT=$PORT $APP_DIR/bin/serve
EOF
}

# ---------------------------------------------------------------- uninstall
do_uninstall() {
  log "Removing the Work Log service"

  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    run systemctl stop "$SERVICE_NAME" || true
    run systemctl disable "$SERVICE_NAME" || true
  fi

  if [[ -f "$UNIT_PATH" ]]; then
    step "removing $UNIT_PATH"
    run rm -f "$UNIT_PATH"
  fi
  if [[ $DRY_RUN -eq 0 ]] && command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
  fi

  if [[ -d "$APP_DIR" ]]; then
    case "$APP_DIR" in
      /|/bin|/boot|/dev|/etc|/lib|/proc|/run|/sbin|/sys|/usr|/var)
        die "refusing to delete $APP_DIR" ;;
    esac
    step "removing $APP_DIR"
    run rm -rf "$APP_DIR"
  fi

  if [[ $PURGE -eq 1 ]]; then
    step "removing $DATA_DIR and $CONF_DIR"
    case "$DATA_DIR" in
      /|/bin|/boot|/dev|/etc|/lib|/proc|/run|/sbin|/sys|/usr|/var)
        die "refusing to delete $DATA_DIR" ;;
    esac
    run rm -rf "$DATA_DIR"
    run rm -rf "$CONF_DIR"
    if id -u "$RUN_USER" >/dev/null 2>&1; then
      step "removing the $RUN_USER user"
      if command -v userdel >/dev/null 2>&1; then
        run userdel "$RUN_USER" || true
        run groupdel "$RUN_USER" || true
      else
        run deluser "$RUN_USER" || true
      fi
    fi
  fi

  printf '\n%s  Work Log has been removed.%s\n' "$C_GREEN" "$C_RESET"
  if [[ $PURGE -eq 0 ]]; then
    cat <<EOF
  Your database is still at $DATA_DIR/work_log.db
  Delete it with: sudo ./install.sh --uninstall --purge
EOF
  fi
}

# -------------------------------------------------------------------- main
if [[ $MODE == "uninstall" ]]; then
  do_uninstall
else
  fetch_source
  do_install
fi
