# dev-flow hooks

`dev-flow` オーケストレーターがプロンプトの指示（LLM の判断）に頼っていた検証・記録・同期を、Claude Code の hooks で**決定的に**実行するスクリプト群です。`setup.sh` が `~/.claude/settings.json` に登録します（`--no-hooks` で省略可）。

## 一覧

| イベント | matcher | スクリプト | 役割 |
|---|---|---|---|
| `SessionStart` | — | `session-start.sh` | `doc/process/state.json` があれば現在フェーズ・次アクション・直近ログをコンテキストに注入 |
| `PreToolUse` | `Agent` | `pre-agent-check.sh` | `phase-*-agent` 起動前に下流スキル存在・state.json 妥当性・階層深さ・フェーズ対応・ループ回数を検証。問題があれば `deny` / `ask` |
| `PostToolUse` | `Write\|Edit` | `state-sync.sh` | `state.json` の JSON 妥当性検証（壊れていれば exit 2 で差し戻し）、`task_checklist.md` フェーズ進捗の自動同期、`flow.log` 記録。`escalation_*.md` 生成時は Slack 通知（opt-in） |
| `PostToolUse` | `Agent` | `agent-complete.sh` | `phase-*-agent` 完了を `flow.log` に記録し所要時間を算出。Phase 2 完了時は人間確認ゲートを念押し |
| `PreToolUse` | `Bash` | `pr-merge-guard.sh` | `gh pr merge` を捕まえ、自動マージ条件を検証。`main`/`develop`/`release/*`/`hotfix/*` 向けは常に `deny`。`feature/*` 向けは CI 全通過・コンフリクトなし・DB 破壊的変更なし（`db-destructive-patterns.txt`）・`--merge` 方式のときだけ `allow` |
| `Stop` | — | `stop-summary.sh` | 直近 10 分以内に dev-flow イベントがあった場合のみ、現在フェーズと次アクションを表示 |

`phase-*-agent` 以外の Agent 呼び出し・`doc/process/` 以外への書き込みでは何もしないため、dev-flow を使わないプロジェクトへの影響はありません。

## 生成されるファイル

- `doc/process/flow.log` — 時系列イベントログ（`event=agent_start|agent_complete|phase_transition|escalation`）。デバッグと所要時間の把握に使います。git 管理して構いません。

## Slack 通知（opt-in）

`~/.claude/settings.json` の `env` に以下を設定すると、エスカレーション報告が生成されたときに Slack へ投稿します。未設定なら外向き通信は一切行いません。

```json
{
  "env": {
    "SLACK_BOT_TOKEN": "xoxb-...",
    "DEV_FLOW_SLACK_CHANNEL": "#dev-flow-alerts"
  }
}
```

## 動作確認

スモークテストを用意しています。gh はスタブに差し替えるためネットワーク不要で、GNU（Linux）/ BSD（macOS）どちらの coreutils でも通ります。

```bash
bash tests/hooks/run.sh
```

hook を変更したら必ずこれを通してください。`stat` / `date` の方言差は `lib.sh` の `file_mtime` / `iso_to_epoch` に閉じ込めているので、新しい hook でもこれらを経由すること。

stdin に hook JSON を渡して単体で実行することもできます。

```bash
cd /path/to/project   # doc/process/state.json があるディレクトリ
echo '{"tool_name":"Write","tool_input":{"file_path":"doc/process/state.json"},"cwd":"'"$PWD"'"}' \
  | ~/.claude/skills/dev-flow/hooks/state-sync.sh
```

Claude Code 内では `/hooks` で登録状況を確認できます。

## 自動マージ（pr-merge-guard.sh）

想定ブランチ構成: `main ← develop ← feature/xxx ← 作業ブランチ（dev/…, qa/…）`。作業ブランチ → `feature/*` の PR だけが自動マージ対象です。

| 環境変数 | 既定 | 意味 |
|---|---|---|
| `DEV_FLOW_AUTO_MERGE_BASE_PATTERN` | `^feature/` | 自動マージを許可するベースブランチの正規表現。保護ブランチ（main/master/develop/release/hotfix）はこの設定に関係なく常に拒否 |

DB 破壊的変更の判定は PR diff の追加行を `db-destructive-patterns.txt` で grep し、Terraform の DB リソース削除（`resource "aws_db_instance"` 等の削除行）も検出します。誤検知は「自動マージしない」側に倒れるだけなので、パターンは広めです。プロジェクト固有のパターンを足す場合はこのファイルに追記してください。

## 設計上の制約（hook では実現しないもの）

- **Phase 2 → 3-4 の自動続行**: hook はエージェントを起動できず、また要件定義後の人間確認は意図的なゲートです。hook はゲートの存在を念押しするだけに留めています。
- **PR マージの「待機」**: hook は待ちません。オーケストレーターも待たず、マージ待ちが出たら終了して次回 `/dev-flow` で再入します（`session-start.sh` が待ち PR を表示）。
