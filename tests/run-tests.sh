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

if [ -n "${MOCK_CURL_FAIL_TOKENS:-}" ]; then
  IFS=',' read -r -a fail_tokens <<< "$MOCK_CURL_FAIL_TOKENS"
  for fail_token in "${fail_tokens[@]}"; do
    if [ "$auth_token" = "$fail_token" ]; then
      echo "{\"ok\":false,\"error\":\"invalid_auth\"}"
      exit 0
    fi
  done
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
  CODEX_SLACK_CHANNEL_ID="C_TEST" \
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
  local fail_tokens="${9:-}"

  local status=0
  HOME="$test_home" \
  PATH="${mock_bin}:${PATH}" \
  MOCK_CURL_CAPTURE="$capture_file" \
  MOCK_CURL_TRACE="$trace_file" \
  MOCK_CURL_FAIL_TOKENS="$fail_tokens" \
  MOCK_CURL_TS="$mock_ts" \
  CODEX_SLACK_USER_TOKEN="$user_token" \
  CODEX_SLACK_BOT_TOKEN="$bot_token" \
  CODEX_SLACK_CHANNEL_ID="C_TEST" \
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
  assert_contains "first_turn_has_request" "$text" "*Prompt:*"
  assert_contains "first_turn_has_answer" "$text" "*Response:*"
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

test_after_agent_payload_is_supported() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-after-agent.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-after-agent.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000777")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "after_agent_exit" "$status"
  assert_contains "after_agent_request_text" "$text" "Ship notify fix"
  assert_contains "after_agent_answer_text" "$text" "Patched and verified"
  assert_file_exists "after_agent_thread_created" "${test_home}/.codex/.slack-thread-thread-after-agent"

  rm -rf "$tmp_dir"
}

test_current_notify_payload_is_supported() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-current.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-current.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000555")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "current_payload_exit" "$status"
  assert_contains "current_payload_request_text" "$text" "Current payload prompt"
  assert_contains "current_payload_answer_text" "$text" "Current payload answer"
  assert_file_exists "current_payload_thread_created" "${test_home}/.codex/.slack-thread-sess-current"

  rm -rf "$tmp_dir"
}

test_hook_event_session_id_is_supported() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-hook-session.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hook-event-session.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000556")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "hook_event_session_exit" "$status"
  assert_contains "hook_event_session_request_text" "$text" "Hook event prompt"
  assert_contains "hook_event_session_answer_text" "$text" "Hook event answer"
  assert_file_exists "hook_event_session_thread_created" "${test_home}/.codex/.slack-thread-sess-hook-event"

  rm -rf "$tmp_dir"
}

test_invalid_session_id_uses_hashed_session_key() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_first="${tmp_dir}/capture-invalid-first.json"
  local capture_second="${tmp_dir}/capture-invalid-second.json"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload1
  local payload2
  payload1=$(jq -n \
    --arg cwd "${tmp_dir}/repo" \
    '{
      event: "agent-turn-complete",
      "session-id": "session:bad/one",
      cwd: $cwd,
      "input-messages": ["Invalid session one"],
      "last-assistant-message": "Answer one"
    }')
  payload2=$(jq -n \
    --arg cwd "${tmp_dir}/repo" \
    '{
      event: "agent-turn-complete",
      "session-id": "session:bad/two",
      cwd: $cwd,
      "input-messages": ["Invalid session two"],
      "last-assistant-message": "Answer two"
    }')

  local status1
  local status2
  status1=$(run_notify "$payload1" "$test_home" "$mock_bin" "$capture_first" "1710000000.000601")
  status2=$(run_notify "$payload2" "$test_home" "$mock_bin" "$capture_second" "1710000000.000602")

  local thread_ts_first
  local thread_ts_second
  thread_ts_first=$(jq -r '.thread_ts // ""' "$capture_first")
  thread_ts_second=$(jq -r '.thread_ts // ""' "$capture_second")
  local sid_thread_count
  sid_thread_count=$(find "${test_home}/.codex" -maxdepth 1 -type f -name '.slack-thread-sid-*' ! -name '*.cwd' | wc -l | tr -d ' ')

  assert_zero "invalid_session_first_exit" "$status1"
  assert_zero "invalid_session_second_exit" "$status2"
  assert_equals "invalid_session_first_no_thread_ts" "$thread_ts_first" ""
  assert_equals "invalid_session_second_no_thread_ts" "$thread_ts_second" ""
  assert_equals "invalid_session_sid_thread_files" "$sid_thread_count" "2"

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

test_dual_tokens_fallback_to_bot_when_user_token_fails_on_first_turn() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-dual-fallback-first.json"
  local trace_file="${tmp_dir}/trace-dual-fallback-first.log"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status
  status=$(run_notify_with_tokens "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000301" "xoxp-user" "xoxb-bot" "$trace_file" "xoxp-user")

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
  local second_text
  second_text=$(printf "%s" "$second_payload" | jq -r '.text // ""')

  assert_zero "dual_tokens_fallback_first_exit" "$status"
  assert_equals "dual_tokens_fallback_first_calls" "$line_count" "2"
  assert_equals "dual_tokens_fallback_first_user_attempt" "$first_token" "xoxp-user"
  assert_equals "dual_tokens_fallback_first_bot_post" "$second_token" "xoxb-bot"
  assert_equals "dual_tokens_fallback_first_no_thread_ts" "$second_thread_ts" ""
  assert_contains "dual_tokens_fallback_first_has_request" "$second_text" "*Prompt:*"
  assert_contains "dual_tokens_fallback_first_has_answer" "$second_text" "*Response:*"

  rm -rf "$tmp_dir"
}

test_changed_files_included_in_notification() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-changes.json"
  local repo_dir="${tmp_dir}/repo"
  mkdir -p "${test_home}/.codex"
  write_mock_curl "$mock_bin"

  # Set up a git repo with an initial commit
  git init "$repo_dir" >/dev/null 2>&1
  git -C "$repo_dir" -c user.name="test" -c user.email="test@test" commit --allow-empty -m "init" >/dev/null 2>&1
  printf "line1\nline2\nline3\n" > "${repo_dir}/existing.txt"
  git -C "$repo_dir" add existing.txt >/dev/null 2>&1
  git -C "$repo_dir" -c user.name="test" -c user.email="test@test" commit -m "add existing" >/dev/null 2>&1

  # Make changes: modify tracked file and add untracked file
  printf "line1\nMODIFIED\nline3\nnewline4\n" > "${repo_dir}/existing.txt"
  printf "brand new content\n" > "${repo_dir}/newfile.txt"

  local payload
  payload=$(jq -n \
    --arg cwd "$repo_dir" \
    '{
      event: "agent-turn-complete",
      "session-id": "sess-changes-test",
      cwd: $cwd,
      "input-messages": ["Make some changes"],
      "last-assistant-message": "Done"
    }')

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000901")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "changed_files_exit" "$status"
  assert_contains "changed_files_has_changes_label" "$text" "*Changes:*"
  assert_contains "changed_files_has_existing" "$text" "existing.txt"
  assert_contains "changed_files_has_existing_diff" "$text" "(+2 -1)"
  assert_contains "changed_files_has_newfile" "$text" "newfile.txt"
  assert_contains "changed_files_has_newfile_diff" "$text" "(+1 -0)"
  assert_contains "changed_files_backtick_wrap" "$text" '`'
  assert_not_contains "changed_files_no_status_prefix" "$text" "M existing.txt"
  assert_not_contains "changed_files_no_diff_label" "$text" "*Diff:*"

  rm -rf "$tmp_dir"
}

test_no_changes_no_changes_block() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-no-changes.json"
  local repo_dir="${tmp_dir}/repo"
  mkdir -p "${test_home}/.codex"
  write_mock_curl "$mock_bin"

  # Set up a clean git repo
  git init "$repo_dir" >/dev/null 2>&1
  printf "clean\n" > "${repo_dir}/clean.txt"
  git -C "$repo_dir" add -A >/dev/null 2>&1
  git -C "$repo_dir" -c user.name="test" -c user.email="test@test" commit -m "init" >/dev/null 2>&1

  local payload
  payload=$(jq -n \
    --arg cwd "$repo_dir" \
    '{
      event: "agent-turn-complete",
      "session-id": "sess-no-changes",
      cwd: $cwd,
      "input-messages": ["Check status"],
      "last-assistant-message": "All clean"
    }')

  local status
  status=$(run_notify "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000902")

  local text
  text=$(jq -r '.text // ""' "$capture_file")

  assert_zero "no_changes_exit" "$status"
  assert_not_contains "no_changes_no_label" "$text" "*Changes:*"

  rm -rf "$tmp_dir"
}

test_dual_tokens_followup_turn_includes_request_and_answer() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-dual-followup.json"
  local trace_file="${tmp_dir}/trace-dual-followup.log"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status1
  local status2
  status1=$(run_notify_with_tokens "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000001" "xoxp-user" "xoxb-bot" "$trace_file")
  status2=$(run_notify_with_tokens "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000002" "xoxp-user" "xoxb-bot" "$trace_file")

  local line_count
  line_count=$(wc -l < "$trace_file" | tr -d ' ')

  local third_token
  local fourth_token
  third_token=$(awk 'NR==3 {print $1}' "$trace_file")
  fourth_token=$(awk 'NR==4 {print $1}' "$trace_file")
  local third_payload
  local fourth_payload
  third_payload=$(awk -F '\t' 'NR==3 {print $2}' "$trace_file")
  fourth_payload=$(awk -F '\t' 'NR==4 {print $2}' "$trace_file")
  local third_thread_ts
  local fourth_thread_ts
  third_thread_ts=$(printf "%s" "$third_payload" | jq -r '.thread_ts // ""')
  fourth_thread_ts=$(printf "%s" "$fourth_payload" | jq -r '.thread_ts // ""')
  local third_text
  local fourth_text
  third_text=$(printf "%s" "$third_payload" | jq -r '.text // ""')
  fourth_text=$(printf "%s" "$fourth_payload" | jq -r '.text // ""')

  assert_zero "dual_tokens_followup_first_call_exit" "$status1"
  assert_zero "dual_tokens_followup_second_call_exit" "$status2"
  assert_equals "dual_tokens_followup_total_posts" "$line_count" "4"
  assert_equals "dual_tokens_followup_third_user_token" "$third_token" "xoxp-user"
  assert_equals "dual_tokens_followup_fourth_bot_token" "$fourth_token" "xoxb-bot"
  assert_equals "dual_tokens_followup_third_thread_ts" "$third_thread_ts" "1710000000.000001"
  assert_equals "dual_tokens_followup_fourth_thread_ts" "$fourth_thread_ts" "1710000000.000001"
  assert_contains "dual_tokens_followup_third_has_request" "$third_text" "*Prompt:*"
  assert_not_contains "dual_tokens_followup_third_no_answer" "$third_text" "*Response:*"
  assert_contains "dual_tokens_followup_fourth_has_answer" "$fourth_text" "*Response:*"
  assert_not_contains "dual_tokens_followup_fourth_no_request" "$fourth_text" "*Prompt:*"

  rm -rf "$tmp_dir"
}

test_dual_tokens_fallback_on_followup_when_user_token_fails() {
  local tmp_dir
  tmp_dir=$(mktemp -d)

  local test_home="${tmp_dir}/home"
  local mock_bin="${tmp_dir}/mock-bin"
  local capture_file="${tmp_dir}/capture-dual-fallback-followup.json"
  local trace_file="${tmp_dir}/trace-dual-fallback-followup.log"
  mkdir -p "${test_home}/.codex" "${tmp_dir}/repo"
  write_mock_curl "$mock_bin"

  local payload
  payload=$(render_fixture "${FIXTURES_DIR}/notify-hyphenated.json" "${tmp_dir}/repo")

  local status1
  local status2
  status1=$(run_notify_with_tokens "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000401" "xoxp-user" "xoxb-bot" "$trace_file")
  status2=$(run_notify_with_tokens "$payload" "$test_home" "$mock_bin" "$capture_file" "1710000000.000402" "xoxp-user" "xoxb-bot" "$trace_file" "xoxp-user")

  local line_count
  line_count=$(wc -l < "$trace_file" | tr -d ' ')
  local third_token
  local fourth_token
  third_token=$(awk 'NR==3 {print $1}' "$trace_file")
  fourth_token=$(awk 'NR==4 {print $1}' "$trace_file")
  local fourth_payload
  fourth_payload=$(awk -F '\t' 'NR==4 {print $2}' "$trace_file")
  local fourth_thread_ts
  fourth_thread_ts=$(printf "%s" "$fourth_payload" | jq -r '.thread_ts // ""')
  local fourth_text
  fourth_text=$(printf "%s" "$fourth_payload" | jq -r '.text // ""')

  assert_zero "dual_tokens_fallback_followup_first_call_exit" "$status1"
  assert_zero "dual_tokens_fallback_followup_second_call_exit" "$status2"
  assert_equals "dual_tokens_fallback_followup_total_posts" "$line_count" "4"
  assert_equals "dual_tokens_fallback_followup_third_user_attempt" "$third_token" "xoxp-user"
  assert_equals "dual_tokens_fallback_followup_fourth_bot_post" "$fourth_token" "xoxb-bot"
  assert_equals "dual_tokens_fallback_followup_thread_ts" "$fourth_thread_ts" "1710000000.000401"
  assert_contains "dual_tokens_fallback_followup_has_request" "$fourth_text" "*Prompt:*"
  assert_contains "dual_tokens_fallback_followup_has_answer" "$fourth_text" "*Response:*"

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
  expected_notify_line="notify = [\"${escaped_notify_path}\"]"
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
  test_after_agent_payload_is_supported
  test_current_notify_payload_is_supported
  test_hook_event_session_id_is_supported
  test_invalid_session_id_uses_hashed_session_key
  test_symlink_thread_file_not_followed
  test_changed_files_included_in_notification
  test_no_changes_no_changes_block
  test_dual_tokens_split_posts
  test_dual_tokens_fallback_to_bot_when_user_token_fails_on_first_turn
  test_dual_tokens_followup_turn_includes_request_and_answer
  test_dual_tokens_fallback_on_followup_when_user_token_fails

  echo "----"
  echo "Passed: ${PASS_COUNT}"
  echo "Failed: ${FAIL_COUNT}"

  if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
  fi
}

main "$@"
