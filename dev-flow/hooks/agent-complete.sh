#!/bin/bash
# PostToolUse (matcher: Agent)
# dev-flow のフェーズエージェント（phase-*-agent）完了時に flow.log へ記録し、
# 直前の agent_start からの所要時間を算出して Claude に返す。

source "$(dirname "$0")/lib.sh"

[ "$(jqi '.tool_name')" = "Agent" ] || exit 0
AGENT="$(jqi '.tool_input.name // empty')"
case "$AGENT" in phase-*-agent) ;; *) exit 0 ;; esac

PHASE="$(current_phase)"

# 所要時間: flow.log 内の同エージェント最後の agent_start 行から
DURATION=""
if [ -f "$FLOW_LOG" ]; then
  START_TS="$(grep "event=agent_start agent=$AGENT " "$FLOW_LOG" | tail -1 | cut -d' ' -f1)"
  if [ -n "$START_TS" ]; then
    START_EPOCH="$(date -d "$START_TS" +%s 2>/dev/null || echo "")"
    [ -n "$START_EPOCH" ] && DURATION=$(( $(date +%s) - START_EPOCH ))
  fi
fi

log_flow "event=agent_complete agent=$AGENT phase=${PHASE:-null}${DURATION:+ duration_seconds=$DURATION}"

MSG="dev-flow hook: $AGENT 完了${DURATION:+（${DURATION}秒）}。state.json current_phase=${PHASE:-null} → 次: $(next_phase_label "$PHASE")。"
if [ "$PHASE" = "phase_2" ]; then
  MSG="$MSG 要件定義は人間確認ゲートです。自動移行せず「確認後 /dev-flow を実行してください」と案内してください。"
fi
post_context "$MSG"
