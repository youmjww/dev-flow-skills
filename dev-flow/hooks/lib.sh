#!/bin/bash
# dev-flow hooks 共通ライブラリ
# 各 hook スクリプトから `source "$(dirname "$0")/lib.sh"` で読み込む。
# stdin の hook JSON を $INPUT に保持し、state.json / task_checklist.md / flow.log のパスを解決する。

set -u

INPUT="$(cat 2>/dev/null || true)"

# stdin JSON からフィールドを取り出す（存在しなければ空文字）
jqi() {
  printf '%s' "$INPUT" | jq -r "$@" 2>/dev/null || true
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(jqi '.cwd // empty')}"
: "${PROJECT_DIR:=$PWD}"

PROCESS_DIR="$PROJECT_DIR/doc/process"
STATE="$PROCESS_DIR/state.json"
CHECKLIST="$PROCESS_DIR/task_checklist.md"
FLOW_LOG="$PROCESS_DIR/flow.log"

# ---------------------------------------------------------------------------
# state.json ヘルパー
# ---------------------------------------------------------------------------

state_exists() { [ -f "$STATE" ]; }

state_valid() { state_exists && jq -e . "$STATE" >/dev/null 2>&1; }

# state.json のフィールドを取得（不正 JSON・欠損時は空文字）
state_get() {
  state_valid || return 0
  jq -r "$1 // empty" "$STATE" 2>/dev/null || true
}

current_phase() { state_get '.current_phase'; }

# current_phase → 進捗ランク。task_checklist.md のフェーズ進捗行 N は rank >= N で [x] になる。
#   1: Phase 1-2 完了  2: Phase 3-4 完了  3: Phase 4.5 完了
#   4: Phase 5 完了    5: Phase 6 完了    6: Phase 7-8 完了
phase_rank() {
  case "${1:-}" in
    phase_2) echo 1 ;;
    phase_4) echo 2 ;;
    phase_4_5 | phase_4_5_mini) echo 3 ;;
    phase_5) echo 4 ;;
    phase_6) echo 5 ;;
    phase_8 | completed | done) echo 6 ;;
    *) echo 0 ;;
  esac
}

# current_phase → 次に実行されるフェーズの表示名
next_phase_label() {
  case "${1:-}" in
    "" | null) echo "Phase 1-2: 要件定義" ;;
    phase_2) echo "Phase 3-4: ドキュメント生成" ;;
    phase_4) echo "Phase 4.5: 整合性チェック" ;;
    phase_4_5) echo "Phase 5: 並列実装" ;;
    phase_4_5_mini) echo "Phase 4.5（mini）: 計画修正" ;;
    phase_5) echo "Phase 6: テスト実行" ;;
    phase_6) echo "Phase 7-8: 準拠チェック・完了" ;;
    phase_8 | completed | done) echo "完了" ;;
    *) echo "不明（$1）" ;;
  esac
}

# current_phase → オーケストレーターが起動するべきエージェント名
expected_agent_for_phase() {
  case "${1:-}" in
    "" | null) echo "phase-requirements-agent" ;;
    phase_2) echo "phase-spec-agent" ;;
    phase_4) echo "phase-consistency-agent" ;;
    phase_4_5) echo "phase-impl-agent" ;;
    phase_4_5_mini) echo "phase-consistency-mini-agent" ;;
    phase_5) echo "phase-test-agent" ;;
    phase_6) echo "phase-compliance-agent" ;;
    *) echo "" ;;
  esac
}

# エージェント名 → 下流スキルファイル
skill_file_for_agent() {
  local base="$HOME/.claude/skills"
  case "${1:-}" in
    phase-requirements-agent) echo "$base/dev-flow-requirements/SKILL.md" ;;
    phase-spec-agent) echo "$base/dev-flow-spec/SKILL.md" ;;
    phase-consistency-agent | phase-consistency-mini-agent) echo "$base/dev-flow-consistency/SKILL.md" ;;
    phase-impl-agent) echo "$base/dev-flow-implementation/SKILL.md" ;;
    phase-test-agent) echo "$base/dev-flow-test/SKILL.md" ;;
    phase-compliance-agent) echo "$base/dev-flow-compliance/SKILL.md" ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# task_checklist.md 同期
# ---------------------------------------------------------------------------

# 「## フェーズ進捗」セクション内の `- [ ] Phase N` 行を current_phase に合わせて [x]/[ ] に揃える。
# 前進・巻き戻し（Phase 7-8 の仕様変更フローで phase_4 に戻す等）の両方に対応する。
sync_checklist() {
  local phase="$1"
  [ -f "$CHECKLIST" ] || return 0
  local rank
  rank="$(phase_rank "$phase")"

  local tmp
  tmp="$(mktemp)"
  awk -v rank="$rank" '
    /^## / { in_progress = ($0 ~ /^## フェーズ進捗/) }
    in_progress && /^- \[[ x]\] Phase / {
      line = 0
      if ($0 ~ /Phase 1-2/) line = 1
      else if ($0 ~ /Phase 3-4/) line = 2
      else if ($0 ~ /Phase 4\.5/) line = 3
      else if ($0 ~ /Phase 5/) line = 4
      else if ($0 ~ /Phase 6/) line = 5
      else if ($0 ~ /Phase 7-8/) line = 6
      if (line > 0) {
        mark = (rank >= line) ? "[x]" : "[ ]"
        sub(/^- \[[ x]\]/, "- " mark)
      }
    }
    { print }
  ' "$CHECKLIST" > "$tmp" && mv "$tmp" "$CHECKLIST"
  rm -f "$tmp" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# flow.log
# ---------------------------------------------------------------------------

# 時系列ログに 1 行追記。形式: `2026-09-03T19:43:00+09:00 event=... key=value ...`
log_flow() {
  [ -d "$PROCESS_DIR" ] || return 0
  printf '%s %s\n' "$(TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$FLOW_LOG"
}

# flow.log に最後に記録された phase=... の値
last_logged_phase() {
  [ -f "$FLOW_LOG" ] || return 0
  grep -o 'phase=[^ ]*' "$FLOW_LOG" 2>/dev/null | tail -1 | cut -d= -f2
}

# flow.log の最終更新が N 秒以内か
flow_log_recent() {
  local within="${1:-600}"
  [ -f "$FLOW_LOG" ] || return 1
  local mtime now
  mtime="$(stat -c %Y "$FLOW_LOG" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  [ $((now - mtime)) -le "$within" ]
}

# ---------------------------------------------------------------------------
# Slack 通知（opt-in）
# ---------------------------------------------------------------------------

# DEV_FLOW_SLACK_CHANNEL と SLACK_BOT_TOKEN が両方設定されている場合のみ送信する。
# 未設定なら何もしない（外向き通信は明示的に有効化した環境に限定する）。
slack_notify() {
  local text="$1"
  [ -n "${DEV_FLOW_SLACK_CHANNEL:-}" ] || return 0
  [ -n "${SLACK_BOT_TOKEN:-}" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0

  local payload
  payload="$(jq -n --arg c "$DEV_FLOW_SLACK_CHANNEL" --arg t "$text" '{channel: $c, text: $t, unfurl_links: false}')"
  curl -sS -m 10 -X POST https://slack.com/api/chat.postMessage \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H 'Content-type: application/json; charset=utf-8' \
    -d "$payload" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# 出力ヘルパー
# ---------------------------------------------------------------------------

# PreToolUse: 実行を拒否して理由を Claude に返す
deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# PreToolUse: 人間に確認を求める
ask() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}

# PostToolUse: Claude に追加コンテキストを返す
post_context() {
  jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
  exit 0
}
