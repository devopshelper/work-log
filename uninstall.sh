#!/usr/bin/env bash
# Convenience wrapper around install.sh --uninstall
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
exec "$here/install.sh" --uninstall "$@"
