#!/bin/bash
# PostToolUse (matcher: Write|Edit)
# doc/process/ 配下への書き込みを監視する。
#   - state.json: JSON 妥当性を検証し、task_checklist.md のフェーズ進捗を current_phase と同期、flow.log に遷移を記録
#   - escalation_*.md: flow.log に記録し、DEV_FLOW_SLACK_CHANNEL が設定されていれば Slack へ通知
# 対象外のファイルでは何もしない。

source "$(dirname "$0")/lib.sh"

FILE="$(jqi '.tool_input.file_path // empty')"
[ -n "$FILE" ] || exit 0

case "$FILE" in
  */doc/process/state.json | doc/process/state.json)
    if ! state_valid; then
      # exit 2: stderr が Claude にフィードバックされる
      echo "dev-flow hook: doc/process/state.json が不正な JSON になりました。直前の書き込みを見直してください（jq . doc/process/state.json でエラー箇所を確認できます）。" >&2
      exit 2
    fi

    PHASE="$(current_phase)"
    PREV="$(last_logged_phase)"

    sync_checklist "$PHASE"

    if [ "${PREV:-}" != "${PHASE:-null}" ]; then
      log_flow "event=phase_transition phase=${PHASE:-null} prev=${PREV:-none} mode=$(state_get '.mode')"
    fi

    post_context "dev-flow hook: state.json 検証 OK。current_phase=${PHASE:-null}（次: $(next_phase_label "$PHASE")）。task_checklist.md のフェーズ進捗は自動同期済みなので手動更新は不要です。"
    ;;

  */doc/process/escalation_*.md | doc/process/escalation_*.md)
    BASENAME="$(basename "$FILE")"
    PHASE="$(current_phase)"
    log_flow "event=escalation file=$BASENAME phase=${PHASE:-null}"

    ABS="$FILE"
    [ -f "$ABS" ] || ABS="$PROJECT_DIR/$FILE"
    TITLE="$(grep -m1 '^# ' "$ABS" 2>/dev/null || echo "# $BASENAME")"
    slack_notify ":rotating_light: dev-flow エスカレーション（$(basename "$PROJECT_DIR")）
${TITLE#\# }
phase=${PHASE:-null} / ファイル: doc/process/$BASENAME
人間の判断が必要です。"
    ;;
esac

exit 0
