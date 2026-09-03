#!/bin/bash
# SessionStart
# 作業ディレクトリに進行中の dev-flow（doc/process/state.json）があれば、
# 現在フェーズと次のアクションをセッション開始時のコンテキストに注入する。
# stdout はそのまま Claude のコンテキストに追加される。

source "$(dirname "$0")/lib.sh"

state_exists || exit 0

if ! state_valid; then
  echo "dev-flow: doc/process/state.json が不正な JSON です。/dev-flow を実行する前に復旧が必要です（reference/error-handling.md 参照）。"
  exit 0
fi

PHASE="$(current_phase)"
MODE="$(state_get '.mode')"
NEXT="$(next_phase_label "$PHASE")"

echo "dev-flow 進行中: current_phase=${PHASE:-null} mode=${MODE:-full} / 次のフェーズ: $NEXT"
if [ "$NEXT" = "完了" ]; then
  echo "dev-flow: フローは完了済みです。新しい要件を始める場合は doc/process/state.json を削除してから /dev-flow を実行してください。"
else
  echo "dev-flow: 続行するには /dev-flow を実行してください。"
fi

if [ -f "$FLOW_LOG" ]; then
  echo "dev-flow 最近のイベント:"
  tail -3 "$FLOW_LOG" | sed 's/^/  /'
fi
exit 0
