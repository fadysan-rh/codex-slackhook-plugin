# Contributing to codex-slack-notify-plugin

Thanks for contributing.

## Documentation Scope

- `README.md` is user-facing documentation.
- `docs/ja/README.md` is the Japanese user-facing documentation.
- `CONTRIBUTING.md` is developer-facing documentation (this file).

When behavior changes for users, update both user docs.
Keep `README.md` and `docs/ja/README.md` structurally aligned so users can find equivalent information in either language.
When implementation, testing, or release process changes, update this file.

## Prerequisites

- `bash`
- `jq`
- `curl`
- Codex CLI (`codex`)
- Windows runtime support: Git Bash (`bash.exe`)
- Optional for Windows installer testing: PowerShell (`pwsh` or Windows PowerShell)

## Repository Layout

| Path | Purpose |
|------|---------|
| `notify/codex-slack-notify.sh` | Main notify script for turn-complete payloads (`agent-turn-complete` / `after_agent` family events) |
| `setup.sh` | Installs/updates `notify` in Codex config on macOS/Linux |
| `setup.ps1` | Installs/updates `notify` in Codex config on Windows |
| `codex-with-slack.sh` | Wrapper that runs `codex -c "notify=\\"...\\""` |
| `tests/run-tests.sh` | Regression tests with a mock Slack API |
| `tests/fixtures/` | Input payload fixtures used by regression tests |
| `docs/ja/README.md` | Japanese user docs |

## Local Development

1. Clone the repository.
2. Run installer if you want to test with real Codex CLI:
   - macOS/Linux: `./setup.sh`
   - Windows: `./setup.ps1`
3. Set environment variables (`CODEX_SLACK_CHANNEL_ID`, tokens, locale, timeout) as needed.
   - Legacy channel fallback: `CODEX_SLACK_CHANNEL`
   - Changed files limit: `CODEX_SLACK_CHANGES_MAX_FILES`
   - Debug controls: `CODEX_SLACK_NOTIFY_DEBUG=1`, optional `CODEX_SLACK_NOTIFY_DEBUG_LOG`

For isolated local checks, prefer a temporary `CODEX_HOME`:

```bash
CODEX_HOME="$(mktemp -d)" ./setup.sh
```

## Testing

Run regression tests:

```bash
tests/run-tests.sh
```

The test suite validates:

- event filtering for supported turn-complete events (`agent-turn-complete` / `agent_turn_complete` / `after_agent` / `after-agent` / `turn-complete` / `turn_complete`)
- first-turn thread creation and second-turn thread reuse
- payload compatibility (hyphenated and underscored keys)
- support for current payload variants (including `hook_event` session fields)
- mrkdwn escaping (`<`, `>`, `&`)
- symlink-safe state handling
- hashed state keys when session IDs contain unsafe filename characters
- changed-files block rendering and clean-repo no-op behavior
- split posting behavior when both user/bot tokens are set
- bot-token fallback when user-token posting fails in dual-token mode
- setup script idempotency for existing `notify` entries

Manual checks still recommended for:

- `CODEX_SLACK_CHANNEL` fallback behavior when `CODEX_SLACK_CHANNEL_ID` is unset
- `turn_id` / `turn-id` footer rendering in Slack message text
- Windows `setup.ps1` path resolution on a real Git-for-Windows environment

## Design Constraints

- Maintain backward compatibility for supported payload key formats.
- Keep safe no-op behavior when prerequisites are missing or config is incomplete.
- Keep channel resolution behavior stable: `CODEX_SLACK_CHANNEL_ID` first, then `CODEX_SLACK_CHANNEL`.
- Preserve state file safety guarantees:
  - write mode `600`
  - symlink protection on thread state paths
  - atomic write/replace behavior

## Release Checklist

1. Run `tests/run-tests.sh`.
2. Run targeted manual smoke checks when relevant:
   - channel fallback (`CODEX_SLACK_CHANNEL`)
   - turn footer (`turn_id` / `turn-id`)
   - Windows installer (`setup.ps1`)
3. Update docs:
   - user behavior and setup changes: `README.md` and `docs/ja/README.md`
   - include new/changed environment variables and defaults in both user docs
   - keep feature tables and configuration sections aligned between EN/JA docs
   - development workflow changes: `CONTRIBUTING.md`
4. Commit and push.
5. Tag release if needed.

## License

By contributing, you agree your contributions are licensed under [MIT](LICENSE).
