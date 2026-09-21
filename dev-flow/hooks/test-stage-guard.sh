#!/bin/bash
# PreToolUse (matcher: Write|Edit|NotebookEdit)
# test ステージ（state.json.next_stage == "test"）ではテストコードを変更できない。
# 「テストが通らないからテストを直す・消す」を機械的に止め、プロダクションコードの修正だけを許す（DocDD）。
#   - テストファイル（*_test.go / test_*.py / *.test.ts / tests/ 配下 等）への Write / Edit → deny
#   - テスト定義書（doc/test-spec/）への Write / Edit → deny（仕様の書き換えも禁止。変えたければ --kind=change）
# それ以外のステージ・ファイルでは何もしない。

source "$(dirname "$0")/lib.sh"

case "$(jqi '.tool_name')" in Write|Edit|NotebookEdit) ;; *) exit 0 ;; esac
[ "$(next_stage)" = "test" ] || exit 0

FILE="$(jqi '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -n "$FILE" ] || exit 0
REL="${FILE#"$PROJECT_DIR"/}"

if is_test_file "$REL"; then
  log_flow "event=test_stage_write_denied file=$REL"
  deny "dev-flow hook: test ステージではテストコード・テスト定義書を変更できません（${REL}）。失敗しているテストの期待値を正として、プロダクションコードを修正してください。テスト自体が誤っていると判断した場合は、エスカレーション報告に理由を書いて人間に判断を仰いでください（--kind=change で仕様から直します）。"
fi
exit 0
