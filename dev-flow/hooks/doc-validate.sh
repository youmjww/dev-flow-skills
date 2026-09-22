#!/bin/bash
# PostToolUse (matcher: Write|Edit)
# dev-flow の成果物（doc/requirements|test-spec|api-spec|infra-spec/*.md, doc/process/task_checklist.md）が
# 書き込まれたら doc-validate.py でスキーマを検証する。
#   ERROR あり → exit 2（stderr が Claude にフィードバックされ、書き直しを促す）
#   ERROR なし → additionalContext で検証済みであることを伝える（WARN があれば併記）
# 対象外のファイル・python3 が無い環境では何もしない。

source "$(dirname "$0")/lib.sh"

FILE="$(jqi '.tool_input.file_path // empty')"
[ -n "$FILE" ] || exit 0

case "$FILE" in
  */doc/requirements/*.md | doc/requirements/*.md | \
  */doc/test-spec/*.md | doc/test-spec/*.md | \
  */doc/api-spec/*.md | doc/api-spec/*.md | \
  */doc/infra-spec/*.md | doc/infra-spec/*.md | \
  */doc/process/task_checklist.md | doc/process/task_checklist.md) ;;
  *) exit 0 ;;
esac

command -v python3 >/dev/null 2>&1 || exit 0

ABS="$FILE"
[ -f "$ABS" ] || ABS="$PROJECT_DIR/$FILE"
[ -f "$ABS" ] || exit 0

OUT="$(python3 "$(dirname "$0")/doc-validate.py" --project-dir "$PROJECT_DIR" "$ABS" 2>&1)"
RC=$?
REL="${ABS#"$PROJECT_DIR"/}"

if [ "$RC" -eq 1 ]; then
  log_flow "event=doc_invalid file=$REL"
  {
    echo "dev-flow hook: $REL がスキーマ違反です。各行の「→」の直し方に従って修正し、同じファイルを書き直してください。"
    printf '%s\n' "$OUT" | grep -E '^(ERROR|WARN)' | sed 's/^/  /'
    N_HEAD="$(printf '%s\n' "$OUT" | grep -c '本文に見出しがありません' || true)"
    if [ "${N_HEAD:-0}" -ge 3 ]; then
      echo "  ヒント: 本文が未完成の項目が ${N_HEAD} 件あります。文書を分割して書いている場合は、ファイル末尾に <!-- dev-flow: in-progress --> を置くと完成まで WARN 扱いになります（完成時に必ず削除。--all 検証ではマーカーの残存が ERROR）。"
    fi
    echo "  同じ違反で 3 回差し戻された場合は、書き直しを繰り返さず blocked として報告してください。"
  } >&2
  exit 2
fi

WARNS="$(printf '%s\n' "$OUT" | grep -E '^WARN' || true)"
if [ -n "$WARNS" ]; then
  post_context "dev-flow hook: $REL のスキーマ検証 OK（警告あり）。
$(printf '%s\n' "$WARNS" | sed 's/^/  /')"
fi
post_context "dev-flow hook: ${REL} のスキーマ検証 OK（ID 形式・重複・covers の実在・implemented_by・本文見出し）。"
