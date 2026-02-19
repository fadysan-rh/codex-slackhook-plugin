# codex-slackhook-plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)
[![Codex CLI](https://img.shields.io/badge/Codex_CLI-Notify_Plugin-0A7B83)](../../README.md)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](../../notify/)

> `notify` を使って、Codex CLI のターン完了を Slack にリアルタイム通知します。
> セッションごとに 1 スレッドへまとめて投稿します。

Claude Code 向けプラグイン: [`cc-slackhook-plugin`](https://github.com/fadysan-rh/cc-slackhook-plugin)

言語: [English](../../README.md) | 日本語

---

## Overview

Codex の `agent-turn-complete` イベントを受けて Slack に投稿します。

```text
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

| 機能 | 条件 | 動作 |
|------|------|------|
| **スレッド通知** | `agent-turn-complete` ごと | 初回ターンは新規スレッド、2回目以降は同一スレッドへ返信します。 |
| **デュアルトークン投稿** | `SLACK_USER_TOKEN` と `SLACK_BOT_TOKEN` が両方設定済み | リクエストは user token、回答は bot token で投稿します。 |
| **単一トークンフォールバック** | どちらか一方のトークンのみ設定 | リクエスト/回答を1投稿にまとめて送信します。 |
| **Slack向けエスケープ** | 全投稿共通 | Slack `mrkdwn` 特殊文字（`<`, `>`, `&`）をエスケープします。 |
| **柔軟なペイロード解析** | ハイフン形式/アンダースコア形式 | event/session/turn/input/output の両キー形式を受け付けます。 |

### Smart Threading

- アクティブなセッションキーごとに 1 スレッド
- タイムアウト超過、または作業ディレクトリ変更時に新規スレッドを開始
- `SLACK_THREAD_TIMEOUT` で調整可能（既定: `1800` 秒）

## Install

### 方法 A: セットアップスクリプト（推奨）

このリポジトリの絶対パスで、Codex の `notify` 設定を自動追加/更新します。

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

必要なら alias 化:

```bash
alias codexs='/path/to/codex-slackhook-plugin/codex-with-slack.sh'
```

### 方法 C: `config.toml` 手動設定

`~/.codex/config.toml` に追加:

```toml
notify = ["/absolute/path/to/codex-slackhook-plugin/notify/codex-slack-notify.sh"]
```

Windows 例:

```toml
notify = ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\path\\to\\codex-slackhook-plugin\\notify\\codex-slack-notify.sh"]
```

## Configuration

環境変数を設定してください（シェル設定ファイルや起動環境など）。

```bash
export SLACK_USER_TOKEN="xoxp-..."   # 任意: リクエスト投稿用
export SLACK_BOT_TOKEN="xoxb-..."    # 任意: 回答投稿用
export SLACK_CHANNEL="C0XXXXXXX"
export SLACK_LOCALE="ja"             # en / ja（既定: en）
export SLACK_THREAD_TIMEOUT="1800"   # 任意、秒
```

| 変数 | 必須 | 説明 |
|------|:----:|------|
| `SLACK_CHANNEL` | Yes | 投稿先 Slack チャンネル ID |
| `SLACK_USER_TOKEN` | 条件付き | デュアルトークン時のリクエスト投稿用トークン |
| `SLACK_BOT_TOKEN` | 条件付き | デュアルトークン時の回答投稿用トークン |
| `SLACK_THREAD_TIMEOUT` | No | 新規スレッド開始までの秒数（既定: `1800`） |
| `SLACK_LOCALE` | No | メッセージ言語: `en` / `ja`（既定: `en`） |
| `SLACK_NOTIFY_DEBUG` | No | `1` でデバッグログ有効化（既定: `0`） |
| `SLACK_NOTIFY_DEBUG_LOG` | No | デバッグログ出力先（既定: `$HOME/.codex/slack-times-debug.log`） |

トークン挙動:

- `SLACK_USER_TOKEN` + `SLACK_BOT_TOKEN`: 投稿分離（Request は user / Answer は bot）
- どちらか一方のみ: そのトークンで 1 投稿
- どちらも未設定: 投稿しない

## Slack App Setup

1. [Slack API](https://api.slack.com/apps) でアプリを作成
2. **OAuth & Permissions** で Bot/User の両トークンに `chat:write` を追加
3. ワークスペースにインストールしてトークンを取得
4. 投稿先チャンネルにアプリを招待（`/invite @your-app`）

## セキュリティノート

- `$HOME/.codex/.slack-thread-*` 配下の state file は権限 `600` で保存
- state file が symlink の場合は使用前にリセット（symlink 経由の書き込み防止）
- デバッグログは既定で無効

## 開発者向けドキュメント

開発環境、テスト手順、アーキテクチャ、リリース手順は以下にまとめています。

- [CONTRIBUTING.md](../../CONTRIBUTING.md)

## License

[MIT](../../LICENSE)
