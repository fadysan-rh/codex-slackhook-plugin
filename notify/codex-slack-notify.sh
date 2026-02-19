#!/bin/bash
set -uo pipefail

DEBUG_ENABLED="${CODEX_SLACK_NOTIFY_DEBUG:-0}"
DEBUG_LOG="${CODEX_SLACK_NOTIFY_DEBUG_LOG:-$HOME/.codex/slack-times-debug.log}"

init_debug_log() {
  if [ "$DEBUG_ENABLED" != "1" ]; then
    return 0
  fi
  local log_dir
  log_dir=$(dirname "$DEBUG_LOG")
  (umask 077 && mkdir -p "$log_dir" && touch "$DEBUG_LOG") 2>/dev/null || return 0
  chmod 600 "$DEBUG_LOG" 2>/dev/null || true
}

debug() {
  if [ "$DEBUG_ENABLED" != "1" ]; then
    return 0
  fi
  echo "[$(date '+%H:%M:%S')] [codex-notify] $*" >> "$DEBUG_LOG"
}

resolve_locale() {
  local raw="${1:-en}"
  raw=$(printf "%s" "$raw" | tr "[:upper:]" "[:lower:]")
  case "$raw" in
    ja|ja-jp|ja_jp|japanese) echo "ja" ;;
    *) echo "en" ;;
  esac
}

i18n_text() {
  local locale="$1"
  local key="$2"
  case "${locale}:${key}" in
    ja:start_label) echo "Codex Session Started" ;;
    en:start_label) echo "Codex Session Started" ;;
    ja:request_label) echo "リクエスト" ;;
    en:request_label) echo "Prompt" ;;
    ja:answer_label) echo "回答" ;;
    en:answer_label) echo "Response" ;;
    ja:repo_dir_label) echo "repo/dir" ;;
    en:repo_dir_label) echo "repo/dir" ;;
    ja:no_details) echo "(詳細なし)" ;;
    en:no_details) echo "(No details)" ;;
    *) echo "$key" ;;
  esac
}

is_target_event() {
  local event="$1"
  case "$event" in
    ""|null|agent-turn-complete|agent_turn_complete|after_agent|after-agent|turn-complete|turn_complete)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

escape_mrkdwn() {
  printf "%s" "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

is_valid_session_id() {
  local sid="$1"
  [ -n "$sid" ] || return 1
  [ "${#sid}" -le 128 ] || return 1
  [[ "$sid" =~ ^[A-Za-z0-9._-]+$ ]]
}

sanitize_state_file_path() {
  local path="$1"
  local label="$2"
  if [ -L "$path" ]; then
    debug "Reset unsafe symlink state file (${label})"
    rm -f "$path" 2>/dev/null || return 1
  fi
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    debug "EXIT: unsafe state file type (${label})"
    return 1
  fi
  return 0
}

write_state_file_atomic() {
  local path="$1"
  local value="$2"
  local dir
  local tmp_file

  dir=$(dirname "$path")
  (umask 077 && mkdir -p "$dir") 2>/dev/null || return 1
  if [ -e "$path" ] && [ ! -f "$path" ] && [ ! -L "$path" ]; then
    return 1
  fi

  tmp_file=$(mktemp "$dir/.slack-state.XXXXXX") || return 1
  if ! printf "%s" "$value" > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  chmod 600 "$tmp_file" 2>/dev/null || true
  if ! mv -f "$tmp_file" "$path"; then
    rm -f "$tmp_file"
    return 1
  fi
  chmod 600 "$path" 2>/dev/null || true
  return 0
}

file_mtime() {
  local file="$1"
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
    return 0
  fi
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
    return 0
  fi
  echo 0
}

hash_text() {
  local value="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$value" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$value" | sha256sum | awk '{print $1}'
    return 0
  fi
  printf "%s" "$value" | md5 | awk '{print $NF}'
}

resolve_session_key() {
  local session_raw="$1"
  local cwd="$2"
  if is_valid_session_id "$session_raw"; then
    printf "%s" "$session_raw"
    return 0
  fi
  if [ -n "$session_raw" ]; then
    # Keep per-session thread separation even when session id has unsafe filename chars.
    printf "sid-%s" "$(hash_text "$session_raw")"
    return 0
  fi
  printf "cwd-%s" "$(hash_text "${cwd:-unknown}")"
}

payload_from_input() {
  if [ "$#" -gt 0 ] && printf "%s" "$1" | jq -e '.' >/dev/null 2>&1; then
    printf "%s" "$1"
    return 0
  fi
  cat
}

extract_last_user_text() {
  local payload="$1"
  printf "%s" "$payload" | jq -r '
    def textify:
      if . == null then ""
      elif type == "string" then .
      elif type == "number" or type == "boolean" then tostring
      elif type == "object" then ((.text // .input_text // .output_text // .content) | textify)
      elif type == "array" then (map(textify) | map(select(length > 0)) | join("\n"))
      else ""
      end;

    (
      ((.["input-messages"] // .input_messages // .hook_event["input-messages"] // .hook_event.input_messages // [])
        | if type == "array" then . else [] end
        | (
            (map(select(type == "object" and ((.role // "") == "user")) | (.content | textify))
              | map(select(length > 0))
              | last) // ""
          ) as $from_role
        | if ($from_role | length) > 0 then
            $from_role
          else
            ((map(textify) | map(select(length > 0)) | last) // "")
          end
      ) // ""
    ) as $from_messages
    | if ($from_messages | length) > 0 then
        $from_messages
      else
        ((.["last-user-message"] // .last_user_message // .lastUserMessage
          // .hook_event["last-user-message"] // .hook_event.last_user_message // .hook_event.lastUserMessage
          // .user_message // .message // "") | textify)
      end
  ' 2>/dev/null || true
}

extract_last_assistant_text() {
  local payload="$1"
  printf "%s" "$payload" | jq -r '
    def textify:
      if . == null then ""
      elif type == "string" then .
      elif type == "number" or type == "boolean" then tostring
      elif type == "object" then ((.text // .input_text // .output_text // .content) | textify)
      elif type == "array" then (map(textify) | map(select(length > 0)) | join("\n"))
      else ""
      end;

    (
      ((.["output-messages"] // .output_messages // .hook_event["output-messages"] // .hook_event.output_messages // [])
        | if type == "array" then . else [] end
        | (
            (map(select(type == "object" and ((.role // "") == "assistant")) | (.content | textify))
              | map(select(length > 0))
              | last) // ""
          ) as $from_role
        | if ($from_role | length) > 0 then
            $from_role
          else
            ((map(textify) | map(select(length > 0)) | last) // "")
          end
      ) // ""
    ) as $from_messages
    | if ($from_messages | length) > 0 then
        $from_messages
      else
        ((.["last-assistant-message"] // .last_assistant_message // .lastAssistantMessage
          // .hook_event["last-assistant-message"] // .hook_event.last_assistant_message // .hook_event.lastAssistantMessage
          // .last_agent_message // "") | textify)
      end
  ' 2>/dev/null || true
}

build_project_info() {
  local cwd="$1"
  if [ -n "$cwd" ] && [ -d "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local repo_name
    local branch_name
    local remote_url
    local org

    repo_name=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
    branch_name=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    remote_url=$(git -C "$cwd" remote get-url origin 2>/dev/null || true)
    org=""
    if [ -n "$remote_url" ]; then
      org=$(echo "$remote_url" | sed -E 's#.*[:/]([^/]+)/[^/]+$#\1#; s#\.git$##')
    fi

    if [ -n "$org" ]; then
      printf "%s:%s/%s" "$org" "$repo_name" "$branch_name"
    else
      printf "%s/%s" "$repo_name" "$branch_name"
    fi
    return 0
  fi

  if [ -n "$cwd" ]; then
    printf "%s" "$(echo "$cwd" | sed "s|^$HOME|~|")"
  else
    printf "unknown"
  fi
}

post_to_slack() {
  local token="$1"
  local channel="$2"
  local text="$3"
  local thread_ts="${4:-}"

  local blocks
  local body
  local response
  local ok

  blocks=$(jq -n --arg text "$text" '[{"type":"section","text":{"type":"mrkdwn","text":$text}}]')

  body=$(jq -n \
    --arg channel "$channel" \
    --arg text "$text" \
    --argjson blocks "$blocks" \
    '{"channel":$channel,"text":$text,"blocks":$blocks}')

  if [ -n "$thread_ts" ]; then
    body=$(printf "%s" "$body" | jq --arg ts "$thread_ts" '. + {"thread_ts":$ts}')
  fi

  response=$(curl -sS -X POST \
    -H 'Content-Type: application/json; charset=utf-8' \
    -H "Authorization: Bearer ${token}" \
    --data "$body" \
    --connect-timeout 10 \
    --max-time 20 \
    "https://slack.com/api/chat.postMessage")

  ok=$(printf "%s" "$response" | jq -r '.ok // false' 2>/dev/null || echo "false")
  if [ "$ok" != "true" ]; then
    debug "Slack API failed response=${response:0:200}"
    return 1
  fi

  printf "%s" "$response"
  return 0
}

append_turn_suffix() {
  local text="$1"
  local turn_id="$2"
  if [ -z "$turn_id" ]; then
    printf "%s" "$text"
    return 0
  fi
  local turn_suffix
  local nl
  nl=$'\n'
  turn_suffix=$(escape_mrkdwn "$turn_id")
  printf "%s%s%s\`turn\`: %s" "$text" "$nl" "$nl" "$turn_suffix"
}

main() {
  init_debug_log

  local locale
  local slack_token
  local user_token
  local bot_token
  local dual_token_mode
  local channel
  local payload

  locale=$(resolve_locale "${CODEX_SLACK_LOCALE:-}")
  user_token="${CODEX_SLACK_USER_TOKEN:-}"
  bot_token="${CODEX_SLACK_BOT_TOKEN:-}"
  slack_token="${bot_token:-${user_token:-}}"
  dual_token_mode="false"
  if [ -n "$user_token" ] && [ -n "$bot_token" ]; then
    dual_token_mode="true"
  fi
  channel="${CODEX_SLACK_CHANNEL_ID:-${CODEX_SLACK_CHANNEL:-}}"

  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi
  if [ -z "$slack_token" ] || [ -z "$channel" ]; then
    debug "EXIT: missing slack token/channel"
    exit 0
  fi

  payload=$(payload_from_input "$@")
  if ! printf "%s" "$payload" | jq -e '.' >/dev/null 2>&1; then
    debug "EXIT: invalid payload json"
    exit 0
  fi

  local event
  event=$(printf "%s" "$payload" | jq -r '.event // .event_name // .type // .hook_name // .["hook-name"] // .hook_event.event // .hook_event.event_name // .hook_event["event-name"] // .hook_event.event_type // .hook_event["event-type"] // .hook_event.type // ""')
  if ! is_target_event "$event"; then
    debug "EXIT: skip event=$event"
    exit 0
  fi

  local cwd
  local session_raw
  local turn_id
  local session_key
  local request_raw
  local answer_raw
  local request_text
  local answer_text
  local project_info

  cwd=$(printf "%s" "$payload" | jq -r '.cwd // .workdir // .current_dir // .["current-dir"] // .hook_event.cwd // .hook_event.workdir // ""')
  session_raw=$(printf "%s" "$payload" | jq -r '.session_id // .sessionId // .["session-id"] // .thread_id // .threadId // .["thread-id"] // .conversation_id // .conversationId // .["conversation-id"] // .run_id // .runId // .["run-id"] // .session.id // .hook_event.session_id // .hook_event.sessionId // .hook_event["session-id"] // .hook_event.thread_id // .hook_event.threadId // .hook_event["thread-id"] // .hook_event.conversation_id // .hook_event.conversationId // .hook_event["conversation-id"] // .hook_event.run_id // .hook_event.runId // .hook_event["run-id"] // .hook_event.session.id // .metadata.session_id // .metadata.sessionId // .metadata["session-id"] // ""')
  turn_id=$(printf "%s" "$payload" | jq -r '.turn_id // .turnId // .["turn-id"] // .hook_event.turn_id // .hook_event.turnId // .hook_event["turn-id"] // ""')
  debug "parsed event=${event:-unknown} session_raw=${session_raw:-empty} turn_id=${turn_id:-empty} cwd=${cwd:-empty}"

  request_raw=$(extract_last_user_text "$payload")
  answer_raw=$(extract_last_assistant_text "$payload")

  if [ -z "$request_raw" ] && [ -z "$answer_raw" ]; then
    debug "EXIT: no request/answer text"
    exit 0
  fi

  session_key=$(resolve_session_key "$session_raw" "$cwd")
  if [ -z "$session_raw" ]; then
    debug "WARN: missing session id, fallback to cwd-based key"
  elif ! is_valid_session_id "$session_raw"; then
    debug "WARN: session id contains unsafe chars, hashed session key is used"
  fi
  project_info=$(build_project_info "$cwd")

  request_text=$(escape_mrkdwn "${request_raw:0:1200}")
  answer_text=$(escape_mrkdwn "${answer_raw:0:1800}")
  project_info=$(escape_mrkdwn "$project_info")

  local thread_file
  local thread_cwd_file
  local thread_timeout
  local thread_ts
  local need_new_thread

  thread_file="$HOME/.codex/.slack-thread-${session_key}"
  thread_cwd_file="${thread_file}.cwd"
  thread_timeout="${CODEX_SLACK_THREAD_TIMEOUT:-1800}"
  thread_ts=""

  if ! [[ "$thread_timeout" =~ ^[0-9]+$ ]]; then
    thread_timeout=1800
  fi

  if ! sanitize_state_file_path "$thread_file" "thread_ts"; then
    exit 0
  fi
  if ! sanitize_state_file_path "$thread_cwd_file" "thread_cwd"; then
    exit 0
  fi

  if [ -f "$thread_file" ]; then
    thread_ts=$(cat "$thread_file" 2>/dev/null || true)
    need_new_thread=false

    if [ -n "$thread_ts" ]; then
      local file_mod
      local now
      local elapsed
      file_mod=$(file_mtime "$thread_file")
      now=$(date +%s)
      elapsed=$((now - file_mod))
      if [ "$elapsed" -ge "$thread_timeout" ]; then
        need_new_thread=true
      fi
    fi

    if [ "$need_new_thread" = "false" ] && [ -f "$thread_cwd_file" ]; then
      local prev_cwd
      prev_cwd=$(cat "$thread_cwd_file" 2>/dev/null || true)
      if [ "$prev_cwd" != "$cwd" ]; then
        need_new_thread=true
      fi
    fi

    if [ "$need_new_thread" = "true" ]; then
      thread_ts=""
      rm -f "$thread_file" "$thread_cwd_file"
    fi
  fi

  if ! write_state_file_atomic "$thread_cwd_file" "$cwd"; then
    debug "EXIT: failed writing thread cwd"
    exit 0
  fi

  local start_label
  local request_label
  local answer_label
  local repo_dir_label
  local no_details

  start_label=$(i18n_text "$locale" "start_label")
  request_label=$(i18n_text "$locale" "request_label")
  answer_label=$(i18n_text "$locale" "answer_label")
  repo_dir_label=$(i18n_text "$locale" "repo_dir_label")
  no_details=$(i18n_text "$locale" "no_details")

  local response
  if [ "$dual_token_mode" = "false" ]; then
    local text
    if [ -n "$thread_ts" ]; then
      if [ -n "$request_text" ] && [ -n "$answer_text" ]; then
        text=$(printf "*%s:*\n%s\n\n*%s:*\n%s" "$request_label" "$request_text" "$answer_label" "$answer_text")
      elif [ -n "$request_text" ]; then
        text=$(printf "*%s:*\n%s" "$request_label" "$request_text")
      elif [ -n "$answer_text" ]; then
        text=$(printf "*%s:*\n%s" "$answer_label" "$answer_text")
      else
        text="$no_details"
      fi
    else
      if [ -n "$request_text" ] && [ -n "$answer_text" ]; then
        text=$(printf "*%s*\n*%s:* %s\n\n*%s:*\n%s\n\n*%s:*\n%s" "$start_label" "$repo_dir_label" "$project_info" "$request_label" "$request_text" "$answer_label" "$answer_text")
      elif [ -n "$request_text" ]; then
        text=$(printf "*%s*\n*%s:* %s\n\n*%s:*\n%s" "$start_label" "$repo_dir_label" "$project_info" "$request_label" "$request_text")
      elif [ -n "$answer_text" ]; then
        text=$(printf "*%s*\n*%s:* %s\n\n*%s:*\n%s" "$start_label" "$repo_dir_label" "$project_info" "$answer_label" "$answer_text")
      else
        text="$no_details"
      fi
    fi

    text=$(append_turn_suffix "$text" "$turn_id")
    text="${text:0:3000}"

    if [ -n "$thread_ts" ]; then
      if ! response=$(post_to_slack "$slack_token" "$channel" "$text" "$thread_ts"); then
        exit 0
      fi
      if ! write_state_file_atomic "$thread_file" "$thread_ts"; then
        debug "WARN: failed refresh thread file"
      fi
    else
      if ! response=$(post_to_slack "$slack_token" "$channel" "$text"); then
        exit 0
      fi
      local new_ts_single
      new_ts_single=$(printf "%s" "$response" | jq -r '.ts // ""' 2>/dev/null)
      if [ -n "$new_ts_single" ] && [ "$new_ts_single" != "null" ]; then
        if ! write_state_file_atomic "$thread_file" "$new_ts_single"; then
          debug "WARN: failed save thread file"
        fi
      fi
    fi
  else
    local starter_message=""
    local bot_message=""

    if [ -n "$thread_ts" ]; then
      local request_message=""
      local posted_any="false"

      if [ -n "$request_text" ]; then
        request_message=$(printf "*%s:*\n%s" "$request_label" "$request_text")
        request_message="${request_message:0:3000}"
        if ! post_to_slack "$user_token" "$channel" "$request_message" "$thread_ts" >/dev/null; then
          exit 0
        fi
        posted_any="true"
      fi

      if [ -n "$answer_text" ]; then
        bot_message=$(printf "*%s:*\n%s" "$answer_label" "$answer_text")
      elif [ "$posted_any" = "false" ] && [ -n "$request_text" ]; then
        bot_message=$(printf "*%s:*\n%s" "$request_label" "$request_text")
      elif [ "$posted_any" = "false" ]; then
        bot_message="$no_details"
      fi

      if [ -n "$bot_message" ]; then
        bot_message=$(append_turn_suffix "$bot_message" "$turn_id")
        bot_message="${bot_message:0:3000}"

        if ! post_to_slack "$bot_token" "$channel" "$bot_message" "$thread_ts" >/dev/null; then
          exit 0
        fi
        posted_any="true"
      fi

      if [ "$posted_any" = "true" ]; then
        if ! write_state_file_atomic "$thread_file" "$thread_ts"; then
          debug "WARN: failed refresh thread file"
        fi
      fi
    else
      if [ -n "$request_text" ]; then
        starter_message=$(printf "*%s*\n*%s:* %s\n\n*%s:*\n%s" "$start_label" "$repo_dir_label" "$project_info" "$request_label" "$request_text")
      else
        starter_message=$(printf "*%s*\n*%s:* %s\n\n%s" "$start_label" "$repo_dir_label" "$project_info" "$no_details")
      fi
      starter_message="${starter_message:0:3000}"

      if ! response=$(post_to_slack "$user_token" "$channel" "$starter_message"); then
        exit 0
      fi

      local new_ts_dual
      new_ts_dual=$(printf "%s" "$response" | jq -r '.ts // ""' 2>/dev/null)
      if [ -z "$new_ts_dual" ] || [ "$new_ts_dual" = "null" ]; then
        exit 0
      fi

      if ! write_state_file_atomic "$thread_file" "$new_ts_dual"; then
        debug "WARN: failed save thread file"
      fi

      if [ -n "$answer_text" ]; then
        bot_message=$(printf "*%s:*\n%s" "$answer_label" "$answer_text")
      elif [ -n "$request_text" ]; then
        bot_message=$(printf "*%s:*\n%s" "$request_label" "$request_text")
      else
        bot_message="$no_details"
      fi
      bot_message=$(append_turn_suffix "$bot_message" "$turn_id")
      bot_message="${bot_message:0:3000}"

      if ! post_to_slack "$bot_token" "$channel" "$bot_message" "$new_ts_dual" >/dev/null; then
        exit 0
      fi
    fi
  fi

  debug "posted turn session=${session_key} event=${event:-unknown} req_len=${#request_raw} ans_len=${#answer_raw} dual_mode=${dual_token_mode}"
  exit 0
}

main "$@"
