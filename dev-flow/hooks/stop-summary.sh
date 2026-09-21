#!/bin/bash
# Stop
# Claude の応答完了時、直近 10 分以内に dev-flow のイベントがあった場合のみ
# 次のステージとアクションを systemMessage でユーザーに表示する。
# dev-flow と無関係な会話ではノイズを出さない。

source "$(dirname "$0")/lib.sh"

state_valid || exit 0
flow_log_recent 600 || exit 0

STAGE="$(next_stage)"
NEXT="$(stage_label "$STAGE")"

if [ "$NEXT" = "完了" ]; then
  MSG="dev-flow: 全ステージ完了 🎉"
elif [ "$STAGE" = "spec" ]; then
  MSG="dev-flow: 要件定義完了（人間確認ゲート）。doc/requirements/ を確認後 /dev-flow で $NEXT へ進みます。"
else
  MSG="dev-flow: 次: ${NEXT}（/dev-flow で続行）"
fi

jq -n --arg m "$MSG" '{systemMessage: $m}'
exit 0
