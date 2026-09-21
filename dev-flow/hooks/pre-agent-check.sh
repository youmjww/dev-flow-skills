#!/bin/bash
# PreToolUse (matcher: Agent)
# dev-flow のステージエージェント（stage-*-agent）起動前に前提条件を検証する。
#   - パーミッションモードが plan（読み取り専用）でないこと
#   - 下流スキルファイルの存在
#   - state.json の存在・JSON 妥当性（requirements を除く）
#   - agent_hierarchy の深さ上限
#   - next_stage と起動エージェントの対応（ズレは人間に確認）
#   - 同一ステージの再実行回数（無限ループ検出）
# 問題があれば permissionDecision=deny/ask で起動を止め、理由を Claude に返す。

source "$(dirname "$0")/lib.sh"

[ "$(jqi '.tool_name')" = "Agent" ] || exit 0
AGENT="$(jqi '.tool_input.name // empty')"
case "$AGENT" in stage-*-agent) ;; *) exit 0 ;; esac

# 0. パーミッションモード（サブエージェントは親のモードを継承するため、plan では書き込みが一切できない）
if [ "$(jqi '.permission_mode // empty')" = "plan" ]; then
  deny "dev-flow hook: プランモード（読み取り専用）では $AGENT を起動できません。サブエージェントは親のパーミッションモードを継承し、ドキュメント生成や実装が書き込めずに止まります。プランモードを抜けてから /dev-flow を再実行してください。"
fi

# 1. 下流スキルファイル
SKILL_FILE="$(skill_file_for_agent "$AGENT")"
if [ -n "$SKILL_FILE" ] && [ ! -f "$SKILL_FILE" ]; then
  deny "dev-flow hook: 下流スキルが見つかりません: $SKILL_FILE 。~/dev-flow-skills/setup.sh を実行してください。"
fi

# 2. state.json（requirements と bootstrap は state.json が無い状態で起動される）
if [ "$AGENT" != "stage-requirements-agent" ] && [ "$AGENT" != "stage-bootstrap-agent" ]; then
  if ! state_exists; then
    deny "dev-flow hook: doc/process/state.json が存在しません。$AGENT は state.json 必須です。requirements から開始するか --from を確認してください。"
  fi
  if ! state_valid; then
    deny "dev-flow hook: doc/process/state.json が不正な JSON です。reference/error-handling.md の「state.json 破損」手順で復旧してください。"
  fi
fi

# 3. 階層深さ
if state_valid; then
  DEPTH="$(state_get '.agent_hierarchy.current_depth')"
  MAX="$(state_get '.agent_hierarchy.max_depth')"
  if [ -n "$DEPTH" ] && [ -n "$MAX" ] && [ "$DEPTH" -ge "$MAX" ] 2>/dev/null; then
    ask "dev-flow hook: agent_hierarchy.current_depth=$DEPTH が max_depth=$MAX に達しています。起動を続けますか？"
  fi
fi

# 4. ステージとエージェントの対応（bootstrap は state.json 無しでのみ起動する導入ステージなので対象外）
STAGE="$(next_stage)"
EXPECTED="$(expected_agent_for_stage "$STAGE")"
if [ "$AGENT" = "stage-bootstrap-agent" ] && state_exists && [ "$STAGE" != "completed" ]; then
  ask "dev-flow hook: 進行中の run（next_stage=${STAGE}）があるのに bootstrap を起動しようとしています。bootstrap は導入時に 1 回だけ実行するものです。続けますか？"
fi
if [ "$AGENT" != "stage-bootstrap-agent" ] && [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$AGENT" ]; then
  ask "dev-flow hook: next_stage=${STAGE:-requirements} に対応するエージェントは $EXPECTED ですが $AGENT を起動しようとしています。--from 指定なら state.json の next_stage を先に更新してください。続けますか？"
fi

# 5. 無限ループ検出（同一ステージが stage_history に 5 回以上）
if state_valid && [ -n "$STAGE" ]; then
  COUNT="$(jq --arg s "$STAGE" '[.harness.stage_history[]? | select(.stage == $s)] | length' "$STATE" 2>/dev/null || echo 0)"
  if [ "${COUNT:-0}" -ge 5 ] 2>/dev/null; then
    ask "dev-flow hook: stage=$STAGE の実行履歴が ${COUNT} 回あります。ループしている可能性があります。続けますか？"
  fi
fi

log_flow "event=agent_start agent=$AGENT stage=${STAGE:-requirements} model=$(jqi '.tool_input.model // "default"')"
exit 0
