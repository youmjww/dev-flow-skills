#!/bin/bash
# PostToolUse (matcher: Agent)
# dev-flow のステージエージェント（stage-*-agent）完了時に flow.log へ記録し、
# 直前の agent_start からの所要時間を算出して Claude に返す。

source "$(dirname "$0")/lib.sh"

[ "$(jqi '.tool_name')" = "Agent" ] || exit 0
AGENT="$(jqi '.tool_input.name // empty')"
case "$AGENT" in stage-*-agent) ;; *) exit 0 ;; esac

STAGE="$(next_stage)"

# 所要時間: flow.log 内の同エージェント最後の agent_start 行から
DURATION=""
if [ -f "$FLOW_LOG" ]; then
  START_TS="$(grep "event=agent_start agent=$AGENT " "$FLOW_LOG" | tail -1 | cut -d' ' -f1)"
  if [ -n "$START_TS" ]; then
    START_EPOCH="$(iso_to_epoch "$START_TS")"
    [ -n "$START_EPOCH" ] && DURATION=$(( $(date +%s) - START_EPOCH ))
  fi
fi

# pane 型サブエージェントは run_in_background=false でも Agent ツール呼び出しが即座に返り、
# 起動直後に PostToolUse が発火する。数秒以内の「完了」は実際には起動しただけなので、
# agent_complete ではなく agent_spawned として記録し、完了は最終回答（task notification）で判断させる。
SPAWN_THRESHOLD="${DEV_FLOW_SPAWN_THRESHOLD:-10}"
if [ -n "$DURATION" ] && [ "$DURATION" -lt "$SPAWN_THRESHOLD" ]; then
  log_flow "event=agent_spawned agent=$AGENT stage=${STAGE:-requirements} duration_seconds=$DURATION"
  post_context "dev-flow hook: $AGENT を起動しました（${DURATION}秒で Agent ツールが返却。実行はまだ完了していません）。完了は最終回答の JSON / task notification で判断してください。タイムアウト目安を過ぎても届かない場合は reference/agent-hang-recovery.md の手順で切り分けてください。"
  exit 0
fi

log_flow "event=agent_complete agent=$AGENT stage=${STAGE:-requirements}${DURATION:+ duration_seconds=$DURATION}"

MSG="dev-flow hook: $AGENT 完了${DURATION:+（${DURATION}秒）}。state.json next_stage=${STAGE:-requirements} → 次: $(stage_label "$STAGE")。"
if [ "$STAGE" = "spec" ]; then
  MSG="$MSG 要件定義は人間確認ゲートです。自動移行せず「確認後 /dev-flow を実行してください」と案内してください。"
fi
post_context "$MSG"
