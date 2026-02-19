# codex-slackhook-plugin

Slack notifications for Codex CLI turns via `notify`.

This repository is separate from `cc-slackhook` (Claude Code plugin) and is dedicated to Codex CLI.

## What it does

When Codex completes a turn (`agent-turn-complete`), this hook posts to Slack:

- First turn in a session: starts a Slack thread
- Later turns: replies in the same thread
- Includes request and answer text
- Escapes Slack `mrkdwn` special chars (`<`, `>`, `&`)

## Files

- `hooks/codex-slack-notify.sh`: main notify hook
- `codex-with-slack.sh`: wrapper that runs `codex -c "notify=[...]"`
- `tests/run-tests.sh`: local regression tests with mock Slack API

## Requirements

- `bash`
- `jq`
- `curl`
- Codex CLI (`codex`)

## Setup

Set env vars (shell profile or launch env):

```bash
export SLACK_BOT_TOKEN="xoxb-..."   # preferred
# export SLACK_USER_TOKEN="xoxp-..." # fallback if bot token is not set
export SLACK_CHANNEL="C0XXXXXXX"
export SLACK_LOCALE="en"             # en / ja (default: en)
export SLACK_THREAD_TIMEOUT="1800"   # optional, seconds
```

### Option A: wrapper script (recommended)

Use the wrapper so notify is always enabled without editing config:

```bash
/path/to/codex-slackhook-plugin/codex-with-slack.sh "your prompt"
```

You can alias it:

```bash
alias codexs='/path/to/codex-slackhook-plugin/codex-with-slack.sh'
```

### Option B: `~/.codex/config.toml`

Add a top-level `notify` command:

```toml
notify = ["/absolute/path/to/codex-slackhook-plugin/hooks/codex-slack-notify.sh"]
```

## Security notes

- Debug logging is **off** by default.
- Enable debug only when needed:

```bash
export SLACK_HOOK_DEBUG=1
export SLACK_HOOK_DEBUG_LOG="$HOME/.codex/slack-times-debug.log"
```

- State files under `$HOME/.codex/.slack-thread-*` are written with mode `600`.
- Symlinked state files are reset before use (symlink-follow write protection).

## Test

```bash
tests/run-tests.sh
```

## License

MIT
