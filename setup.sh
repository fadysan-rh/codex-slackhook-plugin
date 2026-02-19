#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="${SCRIPT_DIR}/notify/codex-slack-notify.sh"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_PATH="${CODEX_HOME_DIR}/config.toml"
tmp_file=""

cleanup() {
  if [ -n "${tmp_file}" ] && [ -f "${tmp_file}" ]; then
    rm -f "${tmp_file}"
  fi
}

trap cleanup EXIT

if [ ! -f "$NOTIFY_SCRIPT" ]; then
  echo "[ERROR] notify script not found: $NOTIFY_SCRIPT" >&2
  exit 1
fi

chmod +x "$NOTIFY_SCRIPT"
mkdir -p "$CODEX_HOME_DIR"

if [ -f "$CONFIG_PATH" ]; then
  backup_path="${CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_PATH" "$backup_path"
  echo "Backed up existing config: $backup_path"
fi

escaped_notify_path=$(printf "%s" "$NOTIFY_SCRIPT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
notify_line="notify = [\"${escaped_notify_path}\"]"

tmp_file=$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")
input_file="$CONFIG_PATH"
if [ ! -f "$input_file" ]; then
  input_file="/dev/null"
fi

awk -v notify_line="$notify_line" '
function emit(s) {
  print s
  output_count += 1
}
BEGIN {
  inserted = 0
  skip_multiline = 0
  output_count = 0
}
{
  line = $0

  if (skip_multiline == 1) {
    if (line ~ /\][[:space:]]*(#.*)?$/) {
      skip_multiline = 0
    }
    next
  }

  if (line ~ /^[[:space:]]*notify[[:space:]]*=/) {
    if (line ~ /\[/ && line !~ /\][[:space:]]*(#.*)?$/) {
      skip_multiline = 1
    }
    next
  }

  if (inserted == 0 && line ~ /^[[:space:]]*\[/) {
    emit(notify_line)
    emit("")
    inserted = 1
  }

  emit(line)
}
END {
  if (inserted == 0) {
    if (output_count > 0) {
      emit("")
    }
    emit(notify_line)
  }
}
' "$input_file" > "$tmp_file"

mv "$tmp_file" "$CONFIG_PATH"
tmp_file=""
chmod 600 "$CONFIG_PATH" 2>/dev/null || true

echo "Installed Codex notify command in: $CONFIG_PATH"
echo "$notify_line"
