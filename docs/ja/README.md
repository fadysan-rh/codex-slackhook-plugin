# codex-slackhook-plugin

`notify` を使って Codex CLI のターン完了を Slack に通知するプラグインです。

Claude Code 用のプラグイン（[`cc-slackhook-plugin`](https://github.com/fadysan-rh/cc-slackhook-plugin)）もあります。

言語: [English](../../README.md) | 日本語

## 機能

Codex のターン完了（`agent-turn-complete`）時に Slack へ投稿します。

- セッション初回は新規スレッドを開始
- 2回目以降は同じスレッドへ返信
- リクエスト/回答テキストを投稿
- Slack `mrkdwn` の特殊文字（`<`, `>`, `&`）をエスケープ
- `SLACK_USER_TOKEN` と `SLACK_BOT_TOKEN` の両方がある場合:
- リクエストは `SLACK_USER_TOKEN` で投稿
- 回答は `SLACK_BOT_TOKEN` で投稿

## ファイル構成

- `notify/codex-slack-notify.sh`: notify スクリプト本体
- `setup.sh`: 絶対パスで Codex の `notify` 設定を自動インストール/更新
- `setup.ps1`: Windows PowerShell 用のインストーラスクリプト
- `codex-with-slack.sh`: `codex -c "notify=[...]"` を付与して実行するラッパー
- `tests/run-tests.sh`: Slack API モック付きの回帰テスト

## 要件

- `bash`
- `jq`
- `curl`
- Codex CLI（`codex`）

## セットアップ

環境変数を設定してください（シェル設定ファイルなど）。

```bash
export SLACK_USER_TOKEN="xoxp-..."   # リクエスト投稿用（任意）
export SLACK_BOT_TOKEN="xoxb-..."    # 回答投稿用（任意）
export SLACK_CHANNEL="C0XXXXXXX"
export SLACK_LOCALE="ja"             # en / ja（既定: en）
export SLACK_THREAD_TIMEOUT="1800"   # 任意、秒
```

トークン挙動:

- `SLACK_USER_TOKEN` + `SLACK_BOT_TOKEN`: 投稿を分離（Request は User / Answer は Bot）
- どちらか片方のみ: 利用可能なトークンで 1 投稿
- どちらも未設定: 投稿しない

### 方法 A: セットアップスクリプト（推奨）

このリポジトリの絶対パスで Codex の `notify` 設定を自動で追加/更新します。

macOS/Linux:

```bash
./setup.sh
```

Windows（PowerShell）:

```powershell
.\setup.ps1
```

`CODEX_HOME` を変更している場合:

```bash
CODEX_HOME="/path/to/codex-home" ./setup.sh
```

```powershell
$env:CODEX_HOME="C:\path\to\codex-home"; .\setup.ps1
```

Windows では `setup.ps1` が `notify = ["bash.exe", ".../notify/codex-slack-notify.sh"]` 形式で設定するため、Git Bash が必要です。

### 方法 B: ラッパー実行

`config.toml` を編集せずに `notify` を有効化できます。

```bash
/path/to/codex-slackhook-plugin/codex-with-slack.sh "your prompt"
```

必要なら alias 化します。

```bash
alias codexs='/path/to/codex-slackhook-plugin/codex-with-slack.sh'
```

### 方法 C: `~/.codex/config.toml`（手動）

トップレベルに `notify` コマンドを追加します。

```toml
notify = ["/absolute/path/to/codex-slackhook-plugin/notify/codex-slack-notify.sh"]
```

Windows 手動設定例:

```toml
notify = ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\path\\to\\codex-slackhook-plugin\\notify\\codex-slack-notify.sh"]
```

## セキュリティノート

- デバッグログは既定で無効です。
- 必要時のみ有効化してください。

```bash
export SLACK_NOTIFY_DEBUG=1
export SLACK_NOTIFY_DEBUG_LOG="$HOME/.codex/slack-times-debug.log"
```

- `$HOME/.codex/.slack-thread-*` 配下の state file は権限 `600` で保存
- state file が symlink の場合は使用前にリセット（symlink 経由の書き込み防止）

## テスト

```bash
tests/run-tests.sh
```

## ライセンス

MIT
