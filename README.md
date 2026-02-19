# codex-slackhook-plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Codex CLI](https://img.shields.io/badge/Codex_CLI-Notify_Plugin-0A7B83)](README.md)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](notify/)

> Real-time Slack notifications for Codex CLI turns via `notify`.
> Prompt and response messages are grouped into one Slack thread per session.

Also available for Claude Code: [`cc-slackhook-plugin`](https://github.com/fadysan-rh/cc-slackhook-plugin)

Language: English | [日本語](docs/ja/README.md)

---

## Overview

When Codex emits a supported turn-complete notification (for example `agent-turn-complete` or `after_agent`), this plugin posts to Slack:

```
You: "Implement authentication"
  ↓
Slack:
       *Codex Session Started*
       *repo/dir:* org:repo/main

       *Prompt:*
       Implement authentication

       *Response:*
       Added JWT middleware and tests
```

## Requirements

- `bash`
- `jq`
- `curl`
- Codex CLI (`codex`)
- `git` (only required for `Changes` block generation)
- Windows runtime: Git Bash (`bash.exe`)

## Features

| Feature | Condition | What it does |
|---------|-----------|--------------|
| **Threaded turn notifications** | Every supported turn-complete event (`agent-turn-complete`, `agent_turn_complete`, `after_agent`, `after-agent`, `turn-complete`, `turn_complete`) | First turn starts a thread, later turns reply in the same thread. |
| **Dual token posting** | `CODEX_SLACK_USER_TOKEN` + `CODEX_SLACK_BOT_TOKEN` are both set | Each turn is split in-thread: `Prompt` is posted with the user token, `Response` is posted with the bot token. If user-token posting fails, it falls back to bot-token posting. |
| **Single token fallback** | Only one token is set | Prompt/response are combined into one post with the available token. |
| **Changed files summary** | Working directory is a Git repository with local changes | Adds a `Changes` block with file paths and line deltas (`+added` / `-deleted`). |
| **Turn ID suffix** | Payload includes `turn_id` / `turn-id` | Appends `turn` metadata at the end of each Slack message to correlate notifications with turn logs. |
| **Slack-safe formatting** | All posts | Escapes Slack `mrkdwn` special characters (`<`, `>`, `&`). |
| **Flexible payload parsing** | Hyphenated and underscored keys | Supports legacy and current Codex notify payloads, including `hook_event.*` and `last-assistant-message` variants. |
| **Safe session-key fallback** | Session IDs are missing or include unsafe filename characters | Uses hashed state keys (`sid-*`/`cwd-*`) to keep thread-state files safe and isolated. |

### Smart Threading

- One Slack thread per active session key
- Starts a new thread when timeout is exceeded or working directory changes
- Timeout is configurable via `CODEX_SLACK_THREAD_TIMEOUT` (default: `1800`)
- Thread state refresh is atomic (temp file + move) with mode `600`

### Changed Files Block

- Generated from `git status --porcelain` and diff stats
- Included only when changes exist
- Maximum files shown can be tuned with `CODEX_SLACK_CHANGES_MAX_FILES` (default: `15`)

## Install

### Option A: setup script (recommended)

Installs/updates `notify` in Codex config using this repository's absolute path.
Safe to rerun: `notify` is kept as a single entry (idempotent update).
If `config.toml` already exists, a timestamped backup (`config.toml.bak.YYYYMMDDHHMMSS`) is created first.

macOS/Linux:

```bash
./setup.sh
```

Windows (PowerShell):

```powershell
.\setup.ps1
```

Custom Codex home:

```bash
CODEX_HOME="/path/to/codex-home" ./setup.sh
```

```powershell
$env:CODEX_HOME="C:\path\to\codex-home"; .\setup.ps1
```

On Windows, `setup.ps1` writes `notify = ["bash.exe", ".../notify/codex-slack-notify.sh"]`, so Git Bash is required.

### Option B: wrapper script

Run Codex with `notify` enabled without editing config:

```bash
/path/to/codex-slackhook-plugin/codex-with-slack.sh "your prompt"
```

Optional alias:

```bash
alias codexs='/path/to/codex-slackhook-plugin/codex-with-slack.sh'
```

### Option C: manual `config.toml`

Add to `~/.codex/config.toml`:

```toml
notify = ["/absolute/path/to/codex-slackhook-plugin/notify/codex-slack-notify.sh"]
```

Windows example:

```toml
notify = ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\path\\to\\codex-slackhook-plugin\\notify\\codex-slack-notify.sh"]
```

## Configuration

Set environment variables in your shell profile (or launch environment):

```bash
export CODEX_SLACK_USER_TOKEN="xoxp-..."   # optional: prompt token
export CODEX_SLACK_BOT_TOKEN="xoxb-..."    # optional: response token
export CODEX_SLACK_CHANNEL_ID="C0XXXXXXX"
export CODEX_SLACK_CHANNEL="C0XXXXXXX"     # optional fallback channel var
export CODEX_SLACK_LOCALE="en"             # en / ja (default: en)
export CODEX_SLACK_THREAD_TIMEOUT="1800"   # optional, seconds
export CODEX_SLACK_CHANGES_MAX_FILES="15"  # optional, changed files listed per post
```

| Variable | Required | Description |
|----------|:--------:|-------------|
| `CODEX_SLACK_CHANNEL_ID` | Conditionally | Preferred target Slack channel ID |
| `CODEX_SLACK_CHANNEL` | Conditionally | Backward-compatible fallback channel variable |
| `CODEX_SLACK_USER_TOKEN` | Conditionally | Token for prompt posting in dual-token mode |
| `CODEX_SLACK_BOT_TOKEN` | Conditionally | Token for response posting in dual-token mode |
| `CODEX_SLACK_THREAD_TIMEOUT` | No | Seconds before starting a new thread (default: `1800`) |
| `CODEX_SLACK_CHANGES_MAX_FILES` | No | Max changed files shown in `Changes` block (default: `15`) |
| `CODEX_SLACK_LOCALE` | No | Message locale: `en` or `ja` (default: `en`) |
| `CODEX_SLACK_NOTIFY_DEBUG` | No | Set `1` to enable debug logs (default: `0`) |
| `CODEX_SLACK_NOTIFY_DEBUG_LOG` | No | Debug log path (default: `$HOME/.codex/slack-times-debug.log`) |

Token rules:

- Both `CODEX_SLACK_USER_TOKEN` and `CODEX_SLACK_BOT_TOKEN`: each turn is split (prompt=user, response=bot)
- If user-token posting fails in dual-token mode: bot-token fallback still posts the turn
- Only one token: combined single post with that token
- No token: no post

Channel rules:

- `CODEX_SLACK_CHANNEL_ID` is used when set
- Otherwise `CODEX_SLACK_CHANNEL` is used
- If neither is set: no post

Minimum required settings to post:

- Channel: set either `CODEX_SLACK_CHANNEL_ID` or `CODEX_SLACK_CHANNEL`
- Token: set at least one of `CODEX_SLACK_BOT_TOKEN` or `CODEX_SLACK_USER_TOKEN`

## Quick Check

After install and environment-variable setup, you can send one test notification using a bundled fixture:

```bash
payload=$(jq --arg cwd "$(pwd)" '.cwd = $cwd' tests/fixtures/notify-current.json)
bash notify/codex-slack-notify.sh "$payload"
```

Expected result:

- One Slack message appears in your configured channel
- The message includes `Codex Session Started`, `Prompt`, `Response`, and a `turn` footer

To inspect why a post was skipped:

```bash
CODEX_SLACK_NOTIFY_DEBUG=1 \
CODEX_SLACK_NOTIFY_DEBUG_LOG=/tmp/codex-slack-debug.log \
bash notify/codex-slack-notify.sh "$payload"
tail -n 50 /tmp/codex-slack-debug.log
```

## Troubleshooting

- No message appears: confirm channel and token environment variables are set, and `jq` is installed.
- Message appears but not on each turn: only turn-complete events are handled (`agent-turn-complete`, `agent_turn_complete`, `after_agent`, `after-agent`, `turn-complete`, `turn_complete`).
- New thread appears unexpectedly: thread state resets when timeout expires (`CODEX_SLACK_THREAD_TIMEOUT`) or when working directory changes.
- `Changes` block is missing: the working directory must be a Git repository with local file changes.
- Windows setup fails: ensure Git for Windows is installed and `bash.exe` is discoverable.

## Slack App Setup

1. Create an app in [Slack API](https://api.slack.com/apps).
2. In **OAuth & Permissions**, add `chat:write` to both Bot Token and User Token scopes.
3. Install the app to your workspace and copy tokens.
4. Invite the app to your target channel (`/invite @your-app`).

## Security Notes

- State files under `$HOME/.codex/.slack-thread-*` are written with mode `600`
- Symlinked state files are reset before use (symlink-follow write protection)
- Thread-state writes use atomic temp-file replacement
- Unsafe session IDs are hashed before being used in state filenames
- Debug logging is disabled by default

## Developer Docs

Development setup, test workflow, architecture notes, and release steps are in:

- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE)
