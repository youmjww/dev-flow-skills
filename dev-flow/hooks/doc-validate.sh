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
    echo "dev-flow hook: $REL がスキーマ違反です。以下を修正して書き直してください（frontmatter の ID・covers・implemented_by・本文見出しの対応を確認）。"
    printf '%s\n' "$OUT" | grep -E '^(ERROR|WARN)' | sed 's/^/  /'
  } >&2
  exit 2
fi

WARNS="$(printf '%s\n' "$OUT" | grep -E '^WARN' || true)"
if [ -n "$WARNS" ]; then
  post_context "dev-flow hook: $REL のスキーマ検証 OK（警告あり）。
$(printf '%s\n' "$WARNS" | sed 's/^/  /')"
fi
post_context "dev-flow hook: ${REL} のスキーマ検証 OK（ID 形式・重複・covers の実在・implemented_by・本文見出し）。"
