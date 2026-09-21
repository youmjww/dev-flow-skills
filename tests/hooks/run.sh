#!/bin/bash
# dev-flow hooks のスモークテスト
#   stdin に hook JSON を渡して各スクリプトを単体実行し、出力（permissionDecision /
#   additionalContext / exit code / 副作用ファイル）を検証する。
#   gh は tests/hooks/fixtures/gh のスタブに差し替えるためネットワーク不要。
#   GNU (Linux) / BSD (macOS) どちらの coreutils でも動くこと。
#
# 使い方: bash tests/hooks/run.sh
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS="$ROOT/dev-flow/hooks"
FIXTURES="$ROOT/tests/hooks/fixtures"

PASS=0
FAIL=0
CURRENT=""

# ---------------------------------------------------------------------------
# アサーション
# ---------------------------------------------------------------------------
ok()   { PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n         %s\n' "$1" "${2:-}"; }

# assert_contains <label> <haystack> <needle>
assert_contains() {
  case "$2" in *"$3"*) ok "$1" ;; *) fail "$1" "expected to contain: $3 / got: $(printf '%s' "$2" | head -c 300)" ;; esac
}
assert_not_contains() {
  case "$2" in *"$3"*) fail "$1" "expected NOT to contain: $3" ;; *) ok "$1" ;; esac
}
assert_eq() { [ "$2" = "$3" ] && ok "$1" || fail "$1" "expected: $3 / got: $2"; }
assert_empty() { [ -z "$2" ] && ok "$1" || fail "$1" "expected empty / got: $(printf '%s' "$2" | head -c 200)"; }

# decision <hook stdout> → permissionDecision の値（無ければ空）
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // .hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

# ---------------------------------------------------------------------------
# テスト用プロジェクトの生成
# ---------------------------------------------------------------------------
new_project() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/dev-flow-hooks-test.XXXXXX")"
  mkdir -p "$dir/doc/process"
  printf '%s\n' "$dir"
}

# write_state <dir> <current_phase | null> [extra jq filter]
write_state() {
  local dir="$1" phase="$2" extra="${3:-.}"
  jq -n --arg p "$phase" '
    {current_phase: (if $p == "null" then null else $p end), mode: "full",
     agent_hierarchy: {max_depth: 4, current_depth: 1},
     harness: {phase_history: []}}' | jq "$extra" > "$dir/doc/process/state.json"
}

write_checklist() {
  cat > "$1/doc/process/task_checklist.md" <<'EOF'
# タスクチェックリスト

## フェーズ進捗
- [ ] Phase 1-2: 要件定義
- [ ] Phase 3-4: ドキュメント生成
- [ ] Phase 4.5: 整合性チェック
- [ ] Phase 5: 並列実装
- [ ] Phase 6: テスト実行
- [ ] Phase 7-8: 準拠チェック

## グループ 1 (App)
- [ ] TASK-001
EOF
}

# run_hook <script> <dir> <json> → stdout。stderr と exit code はファイル経由で hook_err / hook_rc から取れる
# （呼び出し側が $(...) で受けるため、変数では持ち出せない）
HOOK_ERR_FILE="$(mktemp)"
HOOK_RC_FILE="$(mktemp)"
trap 'rm -f "$HOOK_ERR_FILE" "$HOOK_RC_FILE"' EXIT
run_hook() {
  local script="$1" dir="$2" json="$3" rc
  (
    cd "$dir" || exit 1
    export CLAUDE_PROJECT_DIR="$dir" PATH="$FIXTURES:$PATH" GH_FIXTURE_DIR="$FIXTURES"
    printf '%s' "$json" | "$HOOKS/$script" 2>"$HOOK_ERR_FILE"
  )
  rc=$?
  printf '%s' "$rc" > "$HOOK_RC_FILE"
  return 0
}
hook_rc()  { cat "$HOOK_RC_FILE"; }
hook_err() { cat "$HOOK_ERR_FILE"; }

agent_json() { jq -n --arg n "$1" --arg m "${2:-haiku}" '{tool_name:"Agent",tool_input:{name:$n,model:$m}}'; }
bash_json()  { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
write_json() { jq -n --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}'; }

section() { CURRENT="$1"; printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
# lib.sh: GNU/BSD ヘルパー
# ---------------------------------------------------------------------------
section "lib.sh ヘルパー"
(
  # shellcheck disable=SC1091
  source "$HOOKS/lib.sh" </dev/null
  f="$(mktemp)"; touch "$f"
  m="$(file_mtime "$f")"
  now="$(date +%s)"
  [ "$m" -gt 0 ] && [ $((now - m)) -lt 5 ] && ok "file_mtime が現在時刻付近を返す" || fail "file_mtime" "got $m"
  e="$(iso_to_epoch '2026-09-03T19:43:00+0900')"
  assert_eq "iso_to_epoch が固定文字列を epoch に変換する" "$e" "1788432180"
  assert_empty "iso_to_epoch は不正文字列で空を返す" "$(iso_to_epoch 'not-a-date')"
  assert_eq "phase_rank(phase_4_5)" "$(phase_rank phase_4_5)" "3"
  assert_eq "expected_agent_for_phase(phase_5)" "$(expected_agent_for_phase phase_5)" "phase-test-agent"
  assert_eq "next_phase_label(completed)" "$(next_phase_label completed)" "完了"
  rm -f "$f"
  exit $FAIL
)
sub_fail=$?; FAIL=$((FAIL + sub_fail)); PASS=$((PASS + 6 - sub_fail))

# ---------------------------------------------------------------------------
# pre-agent-check.sh
# ---------------------------------------------------------------------------
section "pre-agent-check.sh"
dir="$(new_project)"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json some-other-agent)")"
assert_empty "phase-*-agent 以外は素通り" "$out"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-requirements-agent opus)")"
assert_empty "Phase 1-2 は state.json 無しでも許可" "$out"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-spec-agent)")"
assert_eq "state.json 無しで phase-spec-agent は deny" "$(decision "$out")" "deny"

printf '{broken' > "$dir/doc/process/state.json"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-spec-agent)")"
assert_eq "state.json 不正 JSON は deny" "$(decision "$out")" "deny"

write_state "$dir" phase_2
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-spec-agent)")"
assert_empty "phase_2 + phase-spec-agent は許可（出力なし）" "$out"
assert_contains "agent_start が flow.log に記録される" "$(cat "$dir/doc/process/flow.log")" "event=agent_start agent=phase-spec-agent phase=phase_2"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-test-agent)")"
assert_eq "フェーズとエージェントの不一致は ask" "$(decision "$out")" "ask"
assert_contains "不一致理由に期待エージェント名" "$(reason "$out")" "phase-spec-agent"

write_state "$dir" phase_2 '.agent_hierarchy.current_depth = 4'
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-spec-agent)")"
assert_eq "階層深さ上限で ask" "$(decision "$out")" "ask"

write_state "$dir" phase_2 '.harness.phase_history = [range(5) | {phase:"phase_2"}]'
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-spec-agent)")"
assert_eq "同一フェーズ 5 回で ask（ループ検出）" "$(decision "$out")" "ask"

HOME_BAK="$HOME"; export HOME="$(mktemp -d)"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json phase-spec-agent)")"
assert_eq "下流スキル欠損は deny" "$(decision "$out")" "deny"
export HOME="$HOME_BAK"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# state-sync.sh
# ---------------------------------------------------------------------------
section "state-sync.sh"
dir="$(new_project)"

out="$(run_hook state-sync.sh "$dir" "$(write_json src/main.go)")"
assert_empty "doc/process 以外の書き込みは素通り" "$out"

printf '{broken' > "$dir/doc/process/state.json"
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/state.json)")"
assert_eq "state.json が不正 JSON なら exit 2" "$(hook_rc)" "2"
assert_contains "exit 2 の理由が stderr に出る" "$(hook_err)" "不正な JSON"

write_state "$dir" phase_4_5
write_checklist "$dir"
out="$(run_hook state-sync.sh "$dir" "$(write_json "$dir/doc/process/state.json")")"
assert_eq "正常な state.json は exit 0" "$(hook_rc)" "0"
assert_contains "additionalContext に次フェーズ" "$(reason "$out")" "Phase 5: 並列実装"
cl="$(cat "$dir/doc/process/task_checklist.md")"
assert_contains "Phase 1-2 が [x] に同期" "$cl" "- [x] Phase 1-2"
assert_contains "Phase 4.5 が [x] に同期" "$cl" "- [x] Phase 4.5"
assert_contains "Phase 5 は [ ] のまま" "$cl" "- [ ] Phase 5"
assert_contains "フェーズ進捗以外のチェックボックスは触らない" "$cl" "- [ ] TASK-001"
assert_contains "phase_transition が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=phase_transition phase=phase_4_5"

# 巻き戻し（--from=spec 相当）
write_state "$dir" phase_2
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/state.json)")"
cl="$(cat "$dir/doc/process/task_checklist.md")"
assert_contains "巻き戻しで Phase 3-4 が [ ] に戻る" "$cl" "- [ ] Phase 3-4"
assert_contains "巻き戻しでも Phase 1-2 は [x]" "$cl" "- [x] Phase 1-2"

# escalation
printf '# エスカレーション報告: Phase 6\n' > "$dir/doc/process/escalation_phase_6_20260921.md"
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/escalation_phase_6_20260921.md)")"
assert_eq "escalation 書き込みは exit 0" "$(hook_rc)" "0"
assert_contains "escalation が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=escalation file=escalation_phase_6_20260921.md"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# agent-complete.sh
# ---------------------------------------------------------------------------
section "agent-complete.sh"
dir="$(new_project)"
write_state "$dir" phase_2

out="$(run_hook agent-complete.sh "$dir" "$(agent_json some-other-agent)")"
assert_empty "phase-*-agent 以外は素通り" "$out"

# agent_start を 90 秒前に偽装（log_flow と同じ書式）
ts="$(TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S%z')"
(
  source "$HOOKS/lib.sh" </dev/null
  past="$(( $(iso_to_epoch "$ts") - 90 ))"
  # epoch → ISO（GNU / BSD）
  iso="$(TZ=Asia/Tokyo date -d "@$past" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || TZ=Asia/Tokyo date -j -r "$past" '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s event=agent_start agent=phase-requirements-agent phase=null model=opus\n' "$iso" > "$dir/doc/process/flow.log"
)
out="$(run_hook agent-complete.sh "$dir" "$(agent_json phase-requirements-agent opus)")"
assert_contains "完了が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=agent_complete agent=phase-requirements-agent"
dur="$(grep -o 'duration_seconds=[0-9]*' "$dir/doc/process/flow.log" | cut -d= -f2)"
[ -n "$dur" ] && [ "$dur" -ge 89 ] && [ "$dur" -le 95 ] && ok "所要時間が算出される（GNU/BSD date）" || fail "所要時間" "got: ${dur:-empty}"
assert_contains "phase_2 完了時は人間確認ゲートを念押し" "$(reason "$out")" "人間確認ゲート"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# session-start.sh / stop-summary.sh
# ---------------------------------------------------------------------------
section "session-start.sh / stop-summary.sh"
dir="$(new_project)"

out="$(run_hook session-start.sh "$dir" '{}')"
assert_empty "state.json 無しは何も出さない" "$out"

write_state "$dir" phase_4_5 '.phase_5_progress = {completed_groups:["group-1"], pr_numbers:{"group-1":[101],"group-2":[102]}, base_branch:"feature/xxx"}'
out="$(run_hook session-start.sh "$dir" '{}')"
assert_contains "現在フェーズを表示" "$out" "current_phase=phase_4_5"
assert_contains "マージ待ち PR を表示（完了グループは除外）" "$out" "group-2: PR #102"
assert_not_contains "完了グループの PR は表示しない" "$out" "group-1: PR #101"

out="$(run_hook stop-summary.sh "$dir" '{}')"
assert_empty "flow.log が無ければ stop-summary は沈黙" "$out"
printf '%s event=phase_transition phase=phase_4_5\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$dir/doc/process/flow.log"
out="$(run_hook stop-summary.sh "$dir" '{}')"
assert_contains "直近イベントがあれば systemMessage を出す（file_mtime）" "$(printf '%s' "$out" | jq -r '.systemMessage')" "Phase 5: 並列実装"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# pr-merge-guard.sh
# ---------------------------------------------------------------------------
section "pr-merge-guard.sh（gh はスタブ）"
dir="$(new_project)"
write_state "$dir" phase_4_5 '.phase_5_progress = {base_branch:"feature/xxx"}'

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'git status')")"
assert_empty "gh pr merge を含まないコマンドは素通り" "$out"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 101 --merge && gh pr merge 102 --merge')")"
assert_eq "1 コマンド 2 PR は deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 101 --squash')")"
assert_eq "--squash は deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 101')")"
assert_eq "--merge 省略は deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge --merge')")"
assert_eq "PR 番号省略は deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 101 --merge')")"
assert_eq "条件を満たす PR は allow" "$(decision "$out")" "allow"
assert_contains "allow が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=auto_merge_allowed pr=101"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge https://github.com/o/r/pull/101 --merge')")"
assert_eq "URL 指定でも allow" "$(decision "$out")" "allow"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 102 --merge')")"
assert_eq "main 向けは deny" "$(decision "$out")" "deny"
assert_contains "保護ブランチの理由" "$(reason "$out")" "保護ブランチ"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 103 --merge')")"
assert_eq "CI 失敗は deny" "$(decision "$out")" "deny"
assert_contains "CI 失敗の理由にチェック名" "$(reason "$out")" "ci=FAILURE"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 104 --merge')")"
assert_eq "CI なしは deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 105 --merge')")"
assert_eq "コンフリクトは deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 106 --merge')")"
assert_eq "DB 破壊的変更は deny" "$(decision "$out")" "deny"
assert_contains "DB 破壊的変更の該当行を提示" "$(reason "$out")" "DROP COLUMN"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 107 --merge')")"
assert_eq "Draft は deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 108 --merge')")"
assert_eq "state.json の base_branch と不一致は deny" "$(decision "$out")" "deny"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'gh pr merge 999 --merge')")"
assert_eq "存在しない PR は deny" "$(decision "$out")" "deny"
rm -rf "$dir"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
