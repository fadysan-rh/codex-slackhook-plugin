# codex-slackhook-plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Codex CLI](https://img.shields.io/badge/Codex_CLI-Notify_Plugin-0A7B83)](README.md)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](notify/)

> Real-time Slack notifications for Codex CLI turns via `notify`.
> Request and answer messages are grouped into one Slack thread per session.

Also available for Claude Code: [`cc-slackhook-plugin`](https://github.com/fadysan-rh/cc-slackhook-plugin)

Language: English | [日本語](docs/ja/README.md)

---

## Overview

When Codex emits `agent-turn-complete`, this plugin posts to Slack:

```
You: "Implement authentication"
  ↓
Slack:
       *Codex Session Started*
       *repo/dir:* org:repo/main

       *Request:*
       Implement authentication

       *Answer:*
       Added JWT middleware and tests
```

## Features

| Feature | Condition | What it does |
|---------|-----------|--------------|
| **Threaded turn notifications** | Every `agent-turn-complete` event | First turn starts a thread, later turns reply in the same thread. |
| **Dual token posting** | `SLACK_USER_TOKEN` + `SLACK_BOT_TOKEN` are both set | Request is posted as user token, answer is posted as bot token. |
| **Single token fallback** | Only one token is set | Request/answer are combined into one post with the available token. |
| **Slack-safe formatting** | All posts | Escapes Slack `mrkdwn` special characters (`<`, `>`, `&`). |
| **Flexible payload parsing** | Hyphenated and underscored keys | Supports both formats for event/session/turn/input/output fields. |

### Smart Threading

- One Slack thread per active session key
- Starts a new thread when timeout is exceeded or working directory changes
- Timeout is configurable via `SLACK_THREAD_TIMEOUT` (default: `1800`)

## Install

### Option A: setup script (recommended)

Installs/updates `notify` in Codex config using this repository's absolute path.

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
notify = "/absolute/path/to/codex-slackhook-plugin/notify/codex-slack-notify.sh"
```

Windows example:

```toml
notify = ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\path\\to\\codex-slackhook-plugin\\notify\\codex-slack-notify.sh"]
```

## Configuration

Set environment variables in your shell profile (or launch environment):

```bash
export SLACK_USER_TOKEN="xoxp-..."   # optional: request token
export SLACK_BOT_TOKEN="xoxb-..."    # optional: answer token
export SLACK_CHANNEL="C0XXXXXXX"
export SLACK_LOCALE="en"             # en / ja (default: en)
export SLACK_THREAD_TIMEOUT="1800"   # optional, seconds
```

| Variable | Required | Description |
|----------|:--------:|-------------|
| `SLACK_CHANNEL` | Yes | Target Slack channel ID |
| `SLACK_USER_TOKEN` | Conditionally | Token for request posting in dual-token mode |
| `SLACK_BOT_TOKEN` | Conditionally | Token for answer posting in dual-token mode |
| `SLACK_THREAD_TIMEOUT` | No | Seconds before starting a new thread (default: `1800`) |
| `SLACK_LOCALE` | No | Message locale: `en` or `ja` (default: `en`) |
| `SLACK_NOTIFY_DEBUG` | No | Set `1` to enable debug logs (default: `0`) |
| `SLACK_NOTIFY_DEBUG_LOG` | No | Debug log path (default: `$HOME/.codex/slack-times-debug.log`) |

Token rules:

- Both `SLACK_USER_TOKEN` and `SLACK_BOT_TOKEN`: split posting (request=user, answer=bot)
- Only one token: combined single post with that token
- No token: no post

## Slack App Setup

1. Create an app in [Slack API](https://api.slack.com/apps).
2. In **OAuth & Permissions**, add `chat:write` to both Bot Token and User Token scopes.
3. Install the app to your workspace and copy tokens.
4. Invite the app to your target channel (`/invite @your-app`).

## Security Notes

- State files under `$HOME/.codex/.slack-thread-*` are written with mode `600`
- Symlinked state files are reset before use (symlink-follow write protection)
- Debug logging is disabled by default

## Developer Docs

Development setup, test workflow, architecture notes, and release steps are in:

- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE)
