#!/bin/bash
# SessionStart
# 作業ディレクトリに進行中の dev-flow（doc/process/state.json）があれば、
# 次のステージとアクションをセッション開始時のコンテキストに注入する。
# stdout はそのまま Claude のコンテキストに追加される。

source "$(dirname "$0")/lib.sh"

state_exists || exit 0

if ! state_valid; then
  echo "dev-flow: doc/process/state.json が不正な JSON です。/dev-flow を実行する前に復旧が必要です（reference/error-handling.md 参照）。"
  exit 0
fi

STAGE="$(next_stage)"
MODE="$(state_get '.mode')"
NEXT="$(stage_label "$STAGE")"

echo "dev-flow 進行中: next_stage=${STAGE:-requirements} mode=${MODE:-full} / 次: $NEXT"
if [ "$NEXT" = "完了" ]; then
  echo "dev-flow: フローは完了済みです。新しい要件を始める場合は doc/process/state.json を削除してから /dev-flow を実行してください。"
else
  echo "dev-flow: 続行するには /dev-flow を実行してください。"
fi

# implementation で人間マージ待ちの PR があれば状態を表示（非ブロッキング再入の入口）
if [ "$STAGE" = "implementation" ] && [ "$(state_get '.implementation_progress.pr_numbers | length')" != "" ]; then
  PENDING="$(jq -r '
    .implementation_progress as $p
    | ($p.pr_numbers // {}) | to_entries[]
    | select(.key as $g | ($p.completed_groups // []) | index($g) | not)
    | .key as $g | (.value | if type == "array" then .[] else . end) | select(. != null)
    | "\($g) \(.)"' "$STATE" 2>/dev/null)"
  if [ -n "$PENDING" ]; then
    echo "dev-flow implementation マージ待ち PR:"
    while read -r group num; do
      if command -v gh >/dev/null 2>&1; then
        ST="$(cd "$PROJECT_DIR" && gh pr view "$num" --json state,mergeable,baseRefName --jq '"\(.state) mergeable=\(.mergeable) base=\(.baseRefName)"' 2>/dev/null || echo "状態取得失敗")"
      else
        ST="（gh なし）"
      fi
      echo "  $group: PR #$num $ST"
    done <<< "$PENDING"
    echo "dev-flow: /dev-flow を実行すると MERGED の PR を取り込み、OPEN の PR は自動マージ条件を再判定します。"
  fi
fi

if [ -f "$FLOW_LOG" ]; then
  echo "dev-flow 最近のイベント:"
  tail -3 "$FLOW_LOG" | sed 's/^/  /'
fi
exit 0
