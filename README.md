# codex-slackhook-plugin

Slack notifications for Codex CLI turns via `notify`.

There is also a plugin for Claude Code: [`cc-slackhook-plugin`](https://github.com/fadysan-rh/cc-slackhook-plugin).

Language: English | [日本語](docs/ja/README.md)

## What it does

When Codex completes a turn (`agent-turn-complete`), this notify command posts to Slack:

- First turn in a session: starts a Slack thread
- Later turns: replies in the same thread
- Includes request and answer text
- Escapes Slack `mrkdwn` special chars (`<`, `>`, `&`)
- If both tokens are set, request is posted with `SLACK_USER_TOKEN` and answer with `SLACK_BOT_TOKEN`

## Files

- `notify/codex-slack-notify.sh`: main notify script
- `setup.sh`: installs/updates Codex `notify` config with absolute path
- `setup.ps1`: Windows PowerShell installer for Codex `notify` config
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
export SLACK_USER_TOKEN="xoxp-..."   # request post token (optional)
export SLACK_BOT_TOKEN="xoxb-..."    # answer post token (optional)
export SLACK_CHANNEL="C0XXXXXXX"
export SLACK_LOCALE="en"             # en / ja (default: en)
export SLACK_THREAD_TIMEOUT="1800"   # optional, seconds
```

Token behavior:

- `SLACK_USER_TOKEN` + `SLACK_BOT_TOKEN`: split posting (Request as user, Answer as bot)
- only one token set: single combined post with the available token
- none set: no post

### Option A: setup script (recommended)

Installs `notify` into Codex config using this repository's absolute path.

macOS/Linux:

```bash
./setup.sh
```

Windows (PowerShell):

```powershell
.\setup.ps1
```

If you use a custom Codex home:

```bash
CODEX_HOME="/path/to/codex-home" ./setup.sh
```

```powershell
$env:CODEX_HOME="C:\path\to\codex-home"; .\setup.ps1
```

On Windows, `setup.ps1` configures `notify` as `["bash.exe", ".../notify/codex-slack-notify.sh"]`, so Git Bash is required.

### Option B: wrapper script

Use the wrapper so the notify command is always enabled without editing config:

```bash
/path/to/codex-slackhook-plugin/codex-with-slack.sh "your prompt"
```

You can alias it:

```bash
alias codexs='/path/to/codex-slackhook-plugin/codex-with-slack.sh'
```

### Option C: `~/.codex/config.toml` (manual)

Add a top-level `notify` command:

```toml
notify = ["/absolute/path/to/codex-slackhook-plugin/notify/codex-slack-notify.sh"]
```

Windows manual example:

```toml
notify = ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\path\\to\\codex-slackhook-plugin\\notify\\codex-slack-notify.sh"]
```

## Security notes

- Debug logging is **off** by default.
- Enable debug only when needed:

```bash
export SLACK_NOTIFY_DEBUG=1
export SLACK_NOTIFY_DEBUG_LOG="$HOME/.codex/slack-times-debug.log"
```

- State files under `$HOME/.codex/.slack-thread-*` are written with mode `600`.
- Symlinked state files are reset before use (symlink-follow write protection).

## Test

```bash
tests/run-tests.sh
```

## License

MIT
