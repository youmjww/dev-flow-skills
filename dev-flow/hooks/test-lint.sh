#!/bin/bash
# PostToolUse (matcher: Write|Edit)
# テストコードが書き込まれたら test-lint.py で静的検証する（conventions/testing.md のうち機械判定できるルール）。
#   ERROR（no-skip / assert-present / empty-test / swallowed-error / zero-assertions）→ exit 2 で差し戻し
#   WARN（deterministic / tautology / commented-out / ts-ignore / no-tests）→ additionalContext で通知（reviewer が判断）
# テストファイル以外・python3 が無い環境では何もしない。

source "$(dirname "$0")/lib.sh"

FILE="$(jqi '.tool_input.file_path // empty')"
[ -n "$FILE" ] || exit 0
REL="${FILE#"$PROJECT_DIR"/}"
is_test_code "$REL" || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

ABS="$FILE"
[ -f "$ABS" ] || ABS="$PROJECT_DIR/$FILE"
[ -f "$ABS" ] || exit 0

OUT="$(cd "$PROJECT_DIR" && python3 "$(dirname "$0")/test-lint.py" "$REL" 2>&1)"
RC=$?

if [ "$RC" -eq 1 ]; then
  log_flow "event=test_lint_failed file=$REL"
  {
    echo "dev-flow hook: ${REL} がテストコード規約（conventions/testing.md）に違反しています。ERROR をすべて直して書き直してください。テストを消す・スキップする方向の修正は禁止です。"
    printf '%s\n' "$OUT" | grep -E '^(ERROR|WARN)' | sed 's/^/  /'
  } >&2
  exit 2
fi

WARNS="$(printf '%s\n' "$OUT" | grep -E '^WARN' || true)"
if [ -n "$WARNS" ]; then
  post_context "dev-flow hook: ${REL} の静的検証 OK（警告あり。reviewer が test/deterministic / test/tautology として判断する）。
$(printf '%s\n' "$WARNS" | sed 's/^/  /')"
fi
post_context "dev-flow hook: ${REL} のテストコード静的検証 OK（skip なし・assert あり・握りつぶしなし）。"
