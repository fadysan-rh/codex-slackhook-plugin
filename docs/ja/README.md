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

Codex の対応ターン完了通知（例: `agent-turn-complete` / `after_agent`）を受けて Slack に投稿します。

```text
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

## Features

| 機能 | 条件 | 動作 |
|------|------|------|
| **スレッド通知** | 対応するターン完了イベント（`agent-turn-complete`, `agent_turn_complete`, `after_agent`, `after-agent`, `turn-complete`, `turn_complete`）ごと | 初回ターンは新規スレッド、2回目以降は同一スレッドへ返信します。 |
| **デュアルトークン投稿** | `CODEX_SLACK_USER_TOKEN` と `CODEX_SLACK_BOT_TOKEN` が両方設定済み | 各ターンをスレッド内で分離し、`Prompt` は user token、`Response` は bot token で投稿します。user token 側が失敗した場合は bot token へフォールバックします。 |
| **単一トークンフォールバック** | どちらか一方のトークンのみ設定 | リクエスト/回答を1投稿にまとめて送信します。 |
| **変更ファイル要約** | 作業ディレクトリが Git リポジトリで、ローカル変更がある | `Changes` ブロックに対象ファイルと行差分（`+追加` / `-削除`）を追記します。 |
| **Slack向けエスケープ** | 全投稿共通 | Slack `mrkdwn` 特殊文字（`<`, `>`, `&`）をエスケープします。 |
| **柔軟なペイロード解析** | ハイフン形式/アンダースコア形式 | 旧/現行の Codex notify ペイロードに対応し、`hook_event.*` や `last-assistant-message` の揺れも解析します。 |
| **安全なセッションキー補完** | セッションID欠落、または unsafe な文字を含む | state ファイル名に使うキーをハッシュ化（`sid-*` / `cwd-*`）して安全に分離します。 |

### Smart Threading

- アクティブなセッションキーごとに 1 スレッド
- タイムアウト超過、または作業ディレクトリ変更時に新規スレッドを開始
- `CODEX_SLACK_THREAD_TIMEOUT` で調整可能（既定: `1800` 秒）
- スレッド state の更新は atomic（tmp + move）かつ権限 `600`

### 変更ファイルブロック

- `git status --porcelain` と差分統計から生成
- 変更がある場合のみ投稿に含める
- 表示ファイル数は `CODEX_SLACK_CHANGES_MAX_FILES` で調整可能（既定: `15`）

## Install

### 方法 A: セットアップスクリプト（推奨）

このリポジトリの絶対パスで、Codex の `notify` 設定を自動追加/更新します。
再実行しても `notify` は1件に保たれます（冪等更新）。

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
export CODEX_SLACK_USER_TOKEN="xoxp-..."   # 任意: リクエスト投稿用
export CODEX_SLACK_BOT_TOKEN="xoxb-..."    # 任意: 回答投稿用
export CODEX_SLACK_CHANNEL_ID="C0XXXXXXX"
export CODEX_SLACK_CHANNEL="C0XXXXXXX"     # 任意: 互換チャンネル変数
export CODEX_SLACK_LOCALE="ja"             # en / ja（既定: en）
export CODEX_SLACK_THREAD_TIMEOUT="1800"   # 任意、秒
export CODEX_SLACK_CHANGES_MAX_FILES="15"  # 任意、Changes に出す最大件数
```

| 変数 | 必須 | 説明 |
|------|:----:|------|
| `CODEX_SLACK_CHANNEL_ID` | 条件付き | 優先して使われる投稿先 Slack チャンネル ID |
| `CODEX_SLACK_CHANNEL` | 条件付き | 後方互換用の投稿先チャンネル変数 |
| `CODEX_SLACK_USER_TOKEN` | 条件付き | デュアルトークン時のリクエスト投稿用トークン |
| `CODEX_SLACK_BOT_TOKEN` | 条件付き | デュアルトークン時の回答投稿用トークン |
| `CODEX_SLACK_THREAD_TIMEOUT` | No | 新規スレッド開始までの秒数（既定: `1800`） |
| `CODEX_SLACK_CHANGES_MAX_FILES` | No | `Changes` ブロックに表示する最大ファイル数（既定: `15`） |
| `CODEX_SLACK_LOCALE` | No | メッセージ言語: `en` / `ja`（既定: `en`） |
| `CODEX_SLACK_NOTIFY_DEBUG` | No | `1` でデバッグログ有効化（既定: `0`） |
| `CODEX_SLACK_NOTIFY_DEBUG_LOG` | No | デバッグログ出力先（既定: `$HOME/.codex/slack-times-debug.log`） |

トークン挙動:

- `CODEX_SLACK_USER_TOKEN` + `CODEX_SLACK_BOT_TOKEN`: 各ターンを投稿分離（prompt は user / response は bot）
- デュアルトークン時に user token 投稿が失敗した場合: bot token フォールバックで投稿継続
- どちらか一方のみ: そのトークンで 1 投稿
- どちらも未設定: 投稿しない

チャンネル解決:

- `CODEX_SLACK_CHANNEL_ID` が設定されていればそれを使用
- 未設定の場合のみ `CODEX_SLACK_CHANNEL` を使用
- どちらも未設定なら投稿しない

投稿に必要な最小設定:

- チャンネル: `CODEX_SLACK_CHANNEL_ID` または `CODEX_SLACK_CHANNEL` のどちらかを設定
- トークン: `CODEX_SLACK_BOT_TOKEN` または `CODEX_SLACK_USER_TOKEN` の少なくとも一方を設定

## Quick Check

インストールと環境変数設定後、同梱 fixture で 1 回テスト通知できます。

```bash
payload=$(jq --arg cwd "$(pwd)" '.cwd = $cwd' tests/fixtures/notify-current.json)
bash notify/codex-slack-notify.sh "$payload"
```

期待結果:

- 設定した Slack チャンネルに 1 件投稿される
- 投稿に `Codex Session Started`、`Prompt`、`Response`、`turn` フッターが含まれる

投稿スキップ理由を確認する場合:

```bash
CODEX_SLACK_NOTIFY_DEBUG=1 \
CODEX_SLACK_NOTIFY_DEBUG_LOG=/tmp/codex-slack-debug.log \
bash notify/codex-slack-notify.sh "$payload"
tail -n 50 /tmp/codex-slack-debug.log
```

## Troubleshooting

- 投稿されない: チャンネル/トークン環境変数が設定済みか、`jq` が入っているかを確認
- 毎ターン投稿されない: 対応イベントはターン完了系のみ（`agent-turn-complete`, `agent_turn_complete`, `after_agent`, `after-agent`, `turn-complete`, `turn_complete`）
- 途中で新しいスレッドになる: タイムアウト超過（`CODEX_SLACK_THREAD_TIMEOUT`）か作業ディレクトリ変更で state が切り替わるため
- `Changes` が出ない: 作業ディレクトリが Git リポジトリで、ローカル変更が必要
- Windows で setup が失敗する: Git for Windows を入れ、`bash.exe` が見つかる状態にする

## Slack App Setup

1. [Slack API](https://api.slack.com/apps) でアプリを作成
2. **OAuth & Permissions** で Bot/User の両トークンに `chat:write` を追加
3. ワークスペースにインストールしてトークンを取得
4. 投稿先チャンネルにアプリを招待（`/invite @your-app`）

## セキュリティノート

- `$HOME/.codex/.slack-thread-*` 配下の state file は権限 `600` で保存
- state file が symlink の場合は使用前にリセット（symlink 経由の書き込み防止）
- state 更新は一時ファイル経由の atomic 置換で実施
- unsafe な session ID は state ファイル名に使う前にハッシュ化
- デバッグログは既定で無効

## 開発者向けドキュメント

開発環境、テスト手順、アーキテクチャ、リリース手順は以下にまとめています。

- [CONTRIBUTING.md](../../CONTRIBUTING.md)

## License

[MIT](../../LICENSE)
