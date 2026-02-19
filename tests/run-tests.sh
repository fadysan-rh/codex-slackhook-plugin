#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NOTIFY_SCRIPT="${ROOT_DIR}/notify/codex-slack-notify.sh"
FIXTURES_DIR="${ROOT_DIR}/tests/fixtures"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  local name="$1"
  echo "[PASS] ${name}"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  local name="$1"
  local message="$2"
  echo "[FAIL] ${name}: ${message}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_zero() {
  local name="$1"
  local value="$2"
  if [ "$value" -eq 0 ]; then
    pass "$name"
  else
    fail "$name" "expected 0, got ${value}"
  fi
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "missing: ${needle}"
  fi
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$name" "unexpected: ${needle}"
  else
    pass "$name"
  fi
}

assert_equals() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "expected '${expected}', got '${actual}'"
  fi
}

assert_file_exists() {
  local name="$1"
  local path="$2"
  if [ -f "$path" ]; then
    pass "$name"
  else
    fail "$name" "missing file: ${path}"
  fi
}

assert_file_absent() {
  local name="$1"
  local path="$2"
  if [ -e "$path" ]; then
    fail "$name" "unexpected file: ${path}"
  else
    pass "$name"
  fi
}

write_mock_curl() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"
  cat > "${mock_bin}/curl" <<'EOS'
#!/bin/bash
set -euo pipefail
payload=""
auth_token=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data|--data-binary|--data-raw)
      payload="${2:-}"
      shift 2
      ;;
    -H|--header)
      if [[ "${2:-}" == Authorization:\ Bearer\ * ]]; then
        auth_token="${2#Authorization: Bearer }"
      fi
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "${MOCK_CURL_CAPTURE:-}" ]; then
  printf "%s" "$payload" > "$MOCK_CURL_CAPTURE"
fi
if [ -n "${MOCK_CURL_TRACE:-}" ]; then
  payload_one_line="$payload"
  if command -v jq >/dev/null 2>&1; then
    payload_one_line=$(printf "%s" "$payload" | jq -c . 2>/dev/null || printf "%s" "$payload")
  fi
  printf "%s\t%s\n" "$auth_token" "$payload_one_line" >> "$MOCK_CURL_TRACE"
fi

echo "{\"ok\":true,\"channel\":\"C_TEST\",\"ts\":\"${MOCK_CURL_TS:-1710000000.000001}\"}"
EOS
  chmod +x "${mock_bin}/curl"
}

render_fixture() {
  local fixture="$1"
  local cwd="$2"
  sed "s#__CWD__#${cwd}#g" "$fixture"
}

run_notify() {
  local payload="$1"
  local test_home="$2"
  local mock_bin="$3"
  local capture_file="$4"
  local mock_ts="$5"

  local status=0
  HOME="$test_home" \
  PATH="${mock_bin}:${PATH}" \
  MOCK_CURL_CAPTURE="$capture_file" \
  MOCK_CURL_TS="$mock_ts" \
  CODEX_SLACK_USER_TOKEN="" \
  CODEX_SLACK_BOT_TOKEN="xoxb-test" \
  CODEX_SLACK_CHANNEL="C_TEST" \
    bash "$NOTIFY_SCRIPT" "$payload" >/dev/null 2>&1 || status=$?

  echo "$status"
}

run_notify_with_tokens() {
  local payload="$1"
  local test_home="$2"
  local mock_bin="$3"
  local capture_file="$4"
  local mock_ts="$5"
  local user_token="$6"
  local bot_token="$7"
  local trace_file="$8"

  local status=0
  HOME="$test_home" \
  PATH="${mock_bin}:${PATH}" \
  MOCK_CURL_CAPTURE="$capture_file" \
  MOCK_CURL_TRACE="$trace_file" \
  MOCK_CURL_TS="$mock_ts" \
  CODEX_SLACK_USER_TOKEN="$user_token" \
  CODEX_SLACK_BOT_TOKEN="$bot_token" \
  CODEX_SLACK_CHANNEL="C_TEST" \
    bash "$NOTIFY_SCRIPT" "$payload" >/dev/null 2>&1 || status=$?

  echo "$status"
}

test_ignore_non_target_event() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture.json"
  mkdir -p "${test_home}/.codex"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-other-event.json" "$tmp_dir")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000001")

  assert_zero "ignore_other_event_exit" "$status"
  assert_file_absent "ignore_other_event_no_post" "$capture_file"

  rm -rf "$tmp_dir"
}

test_first_turn_starts_thread() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-first.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000001")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "first_turn_exit" "$status"
  assert_contains "first_turn_has_start" "$text" "*Codex Session Started*"
  assert_contains "first_turn_has_request" "$text" "*Request:*"
  assert_contains "first_turn_has_answer" "$text" "*Answer:*"
  assert_contains "first_turn_escape_channel" "$text" "&lt;!channel&gt;"
  assert_not_contains "first_turn_no_raw_channel" "$text" "<!channel>"
  assert_contains "first_turn_escape_angle" "$text" "&lt;ok&gt;"

  assert_file_exists "first_turn_thread_file_created" "${test_home}/.codex/.slack-thread-sess-123"
  assert_file_exists "first_turn_thread_cwd_file_created" "${test_home}/.codex/.slack-thread-sess-123.cwd"

  rm -rf "$tmp_dir"
}

test_second_turn_reuses_thread() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_first="${tmp_dir}/capture-first.json"
  local capture_second="${tmp_dir}/capture-second.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status1
  status1=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_first" "1710000000.000111")

  local status2
  status2=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_second" "1710000000.000222")

  local thread_ts
  thread_ts=$(jq -r '.thread_ts // ""' "$capture_second")

  assert_zero "second_turn_first_call_exit" "$status1"
  assert_zero "second_turn_second_call_exit" "$status2"
  assert_contains "second_turn_has_thread_ts" "$thread_ts" "1710000000.000111"

  rm -rf "$tmp_dir"
}

test_underscored_keys_are_supported() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-under.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-underscored.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000001")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "underscored_keys_exit" "$status"
  assert_contains "underscored_keys_text" "$text" "Please summarize changes"
  assert_contains "underscored_keys_answer" "$text" "Summary ready"
  assert_file_exists "underscored_keys_thread_created" "${test_home}/.codex/.slack-thread-sess_underscore"

  rm -rf "$tmp_dir"
}

test_symlink_thread_file_not_followed() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-symlink.json"
  local victim_file="${tmp_dir}/victim.txt"
  local thread_file="${test_home}/.codex/.slack-thread-sess-123"

  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  printf "ORIGINAL" > "$victim_file"
  ln -s "$victim_file" "$thread_file"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000001")

  local victim_after
  victim_after=$(cat "$victim_file")

  assert_zero "symlink_thread_exit" "$status"
  assert_contains "symlink_thread_victim_unchanged" "$victim_after" "ORIGINAL"

  if [ -L "$thread_file" ]; then
    fail "symlink_thread_replaced" "thread file remained symlink"
  else
    pass "symlink_thread_replaced"
  fi

  rm -rf "$tmp_dir"
}

test_dual_tokens_split_posts() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-dual.json"
  local trace_file="${tmp_dir}/trace-dual.log"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify_with_tokens "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000001" "xoxp-user" "xoxb-bot" "$trace_file")

  local line_count
  line_count=$(wc -l < "$trace_file" | tr -d ' ')
  local first_token
  local second_token
  first_token=$(awk 'NR==1 {print $1}' "$trace_file")
  second_token=$(awk 'NR==2 {print $1}' "$trace_file")
  local second_payload
  second_payload=$(awk -F '\t' 'NR==2 {print $2}' "$trace_file")
  local second_thread_ts
  second_thread_ts=$(printf "%s" "$second_payload" | jq -r '.thread_ts // ""')

  assert_zero "dual_tokens_exit" "$status"
  assert_equals "dual_tokens_two_posts" "$line_count" "2"
  assert_equals "dual_tokens_first_user_token" "$first_token" "xoxp-user"
  assert_equals "dual_tokens_second_bot_token" "$second_token" "xoxb-bot"
  assert_equals "dual_tokens_second_has_thread_ts" "$second_thread_ts" "1710000000.000001"

  rm -rf "$tmp_dir"
}

test_setup_script_is_idempotent() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/codex-home"
  local config_path="${test_home}/config.toml"
  mkdir -p "$test_home"

  cat > "$config_path" <<'EOF'
model = "gpt-5"
notify = "/legacy/top.sh"

[notice]
hide_gpt5_1_migration_prompt = true

[notice.model_migrations]
"gpt-5.2" = "gpt-5.2-codex"
notify = [
  "/legacy/array.sh"
]
notify = "/legacy/late.sh"
EOF

  CODEX_HOME="$test_home" bash "${ROOT_DIR}/setup.sh" >/dev/null 2>&1
  CODEX_HOME="$test_home" bash "${ROOT_DIR}/setup.sh" >/dev/null 2>&1

  local notify_lines
  notify_lines=$(rg -n '^[[:space:]]*notify[[:space:]]*=' "$config_path" || true)
  local notify_count
  if [ -n "$notify_lines" ]; then
    notify_count=$(printf "%s\n" "$notify_lines" | wc -l | tr -d ' ')
  else
    notify_count="0"
  fi

  local escaped_notify_path
  escaped_notify_path=$(printf "%s" "${ROOT_DIR}/notify/codex-slack-notify.sh" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  local expected_notify_line
  expected_notify_line="notify = \"${escaped_notify_path}\""
  local actual_notify_line
  actual_notify_line=$(printf "%s\n" "$notify_lines" | sed -E 's/^[0-9]+:[[:space:]]*//' | head -n 1)

  local config_text
  config_text=$(cat "$config_path")
  local notify_line_no
  notify_line_no=$(printf "%s\n" "$notify_lines" | head -n 1 | cut -d: -f1)
  local first_section_line_no
  first_section_line_no=$(rg -n '^[[:space:]]*\[' "$config_path" | head -n 1 | cut -d: -f1)

  assert_equals "setup_idempotent_single_notify_line" "$notify_count" "1"
  assert_equals "setup_idempotent_notify_line_value" "$actual_notify_line" "$expected_notify_line"
  assert_not_contains "setup_idempotent_removed_legacy_top" "$config_text" "/legacy/top.sh"
  assert_not_contains "setup_idempotent_removed_legacy_array" "$config_text" "/legacy/array.sh"
  assert_not_contains "setup_idempotent_removed_legacy_late" "$config_text" "/legacy/late.sh"

  if [ -n "$first_section_line_no" ] && [ "$notify_line_no" -lt "$first_section_line_no" ]; then
    pass "setup_idempotent_notify_before_sections"
  else
    fail "setup_idempotent_notify_before_sections" "notify line must appear before first table section"
  fi

  rm -rf "$tmp_dir"
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[FAIL] setup: jq is required"
    exit 1
  fi

  test_setup_script_is_idempotent
  test_ignore_non_target_event
  test_first_turn_starts_thread
  test_second_turn_reuses_thread
  test_underscored_keys_are_supported
  test_symlink_thread_file_not_followed
  test_dual_tokens_split_posts

  echo "----"
  echo "Passed: ${PASS_COUNT}"
  echo "Failed: ${FAIL_COUNT}"

  if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
  fi
}

main "$@"
