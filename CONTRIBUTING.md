# Contributing to codex-slackhook-plugin

Thanks for contributing.

## Documentation Scope

- `README.md` is user-facing documentation.
- `docs/ja/README.md` is the Japanese user-facing documentation.
- `CONTRIBUTING.md` is developer-facing documentation (this file).

When behavior changes for users, update both user docs.
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
| `notify/codex-slack-notify.sh` | Main notify script for `agent-turn-complete` payloads |
| `setup.sh` | Installs/updates `notify` in Codex config on macOS/Linux |
| `setup.ps1` | Installs/updates `notify` in Codex config on Windows |
| `codex-with-slack.sh` | Wrapper that runs `codex -c "notify=[...]"` |
| `tests/run-tests.sh` | Regression tests with a mock Slack API |
| `tests/fixtures/` | Input payload fixtures used by regression tests |
| `docs/ja/README.md` | Japanese user docs |

## Local Development

1. Clone the repository.
2. Run installer if you want to test with real Codex CLI:
   - macOS/Linux: `./setup.sh`
   - Windows: `./setup.ps1`
3. Set environment variables (`SLACK_CHANNEL`, tokens, locale, timeout) as needed.

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

- event filtering (`agent-turn-complete` only)
- first-turn thread creation and second-turn thread reuse
- payload compatibility (hyphenated and underscored keys)
- mrkdwn escaping (`<`, `>`, `&`)
- symlink-safe state handling
- split posting behavior when both user/bot tokens are set

## Design Constraints

- Maintain backward compatibility for supported payload key formats.
- Keep safe no-op behavior when prerequisites are missing or config is incomplete.
- Preserve state file safety guarantees:
  - write mode `600`
  - symlink protection on thread state paths

## Release Checklist

1. Run `tests/run-tests.sh`.
2. Update docs:
   - user behavior and setup changes: `README.md` and `docs/ja/README.md`
   - development workflow changes: `CONTRIBUTING.md`
3. Commit and push.
4. Tag release if needed.

## License

By contributing, you agree your contributions are licensed under [MIT](LICENSE).
