#!/bin/bash
# PostToolUse (matcher: Write|Edit)
# doc/process/ 配下への書き込みを監視する。
#   - state.json: JSON 妥当性を検証し、task_checklist.md のステージ進捗を next_stage と同期、flow.log に遷移を記録
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

    STAGE="$(next_stage)"
    case "$STAGE" in
      "" | requirements | spec | consistency | plan_repair | implementation | test | compliance | completed) ;;
      *)
        echo "dev-flow hook: state.json の next_stage='${STAGE}' は不正です。requirements / spec / consistency / plan_repair / implementation / test / compliance / completed のいずれかにしてください。" >&2
        exit 2 ;;
    esac
    KIND="$(state_get '.kind')"
    case "$KIND" in
      "" | feature | change | fix | refactor | bootstrap) ;;
      *)
        echo "dev-flow hook: state.json の kind='${KIND}' は不正です。feature / change / fix / refactor のいずれかにしてください。" >&2
        exit 2 ;;
    esac
    PREV="$(last_logged_stage)"

    sync_checklist "$STAGE"

    if [ "${PREV:-}" != "${STAGE:-requirements}" ]; then
      log_flow "event=stage_transition stage=${STAGE:-requirements} prev=${PREV:-none} mode=$(state_get '.mode')"
    fi

    post_context "dev-flow hook: state.json 検証 OK。next_stage=${STAGE:-requirements}（$(stage_label "$STAGE")）。task_checklist.md のステージ進捗は自動同期済みなので手動更新は不要です。"
    ;;

  */doc/process/escalation_*.md | doc/process/escalation_*.md)
    BASENAME="$(basename "$FILE")"
    STAGE="$(next_stage)"
    log_flow "event=escalation file=$BASENAME stage=${STAGE:-requirements}"

    ABS="$FILE"
    [ -f "$ABS" ] || ABS="$PROJECT_DIR/$FILE"
    TITLE="$(grep -m1 '^# ' "$ABS" 2>/dev/null || echo "# $BASENAME")"
    slack_notify ":rotating_light: dev-flow エスカレーション（$(basename "$PROJECT_DIR")）
${TITLE#\# }
stage=${STAGE:-requirements} / ファイル: doc/process/$BASENAME
人間の判断が必要です。"
    ;;
esac

exit 0
