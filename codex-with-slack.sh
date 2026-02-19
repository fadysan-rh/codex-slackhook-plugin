#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="${SCRIPT_DIR}/notify/codex-slack-notify.sh"

exec codex -c "notify=\"${NOTIFY_SCRIPT}\"" "$@"
