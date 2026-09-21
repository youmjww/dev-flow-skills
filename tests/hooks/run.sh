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

# 下流スキルの存在チェックはリポジトリ内のスキルを指す偽 HOME で行う（インストール状態に依存しない）
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dev-flow-hooks-home.XXXXXX")"
mkdir -p "$FAKE_HOME/.claude/skills"
for d in "$ROOT"/dev-flow*/; do
  d="${d%/}"
  ln -s "$d" "$FAKE_HOME/.claude/skills/$(basename "$d")"
done
export HOME="$FAKE_HOME"

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

# write_state <dir> <next_stage | null> [extra jq filter]
write_state() {
  local dir="$1" stage="$2" extra="${3:-.}"
  jq -n --arg s "$stage" '
    {next_stage: (if $s == "null" then null else $s end), mode: "full",
     agent_hierarchy: {max_depth: 4, current_depth: 1},
     harness: {stage_history: []}}' | jq "$extra" > "$dir/doc/process/state.json"
}

write_checklist() {
  cat > "$1/doc/process/task_checklist.md" <<'EOF'
# タスクチェックリスト

## ステージ進捗
- [ ] 1. requirements: 要件定義
- [ ] 2. spec: 仕様書生成
- [ ] 3. consistency: 整合性チェック
- [ ] 4. implementation: 並列実装
- [ ] 5. test: テスト実行
- [ ] 6. compliance: 準拠チェック

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

agent_json() { jq -n --arg n "$1" --arg m "${2:-haiku}" --arg pm "${3:-acceptEdits}" '{tool_name:"Agent",permission_mode:$pm,tool_input:{name:$n,model:$m}}'; }
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
  assert_eq "stage_rank(implementation)" "$(stage_rank implementation)" "3"
  assert_eq "expected_agent_for_stage(test)" "$(expected_agent_for_stage test)" "stage-test-agent"
  assert_contains "stage_label(completed)" "$(stage_label completed)" "完了"
  assert_eq "legacy_stage(phase_4_5_mini) は旧値を読み替える" "$(legacy_stage phase_4_5_mini)" "plan_repair"
  rm -f "$f"
  exit $FAIL
)
sub_fail=$?; FAIL=$((FAIL + sub_fail)); PASS=$((PASS + 7 - sub_fail))

# ---------------------------------------------------------------------------
# 静的チェック
# ---------------------------------------------------------------------------
section "静的チェック"
# bash 3.2 は `$VAR（` のように変数名の直後にマルチバイト文字が続くと変数名を誤認して unbound variable になる
bad="$(grep -nP '\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]' "$HOOKS"/*.sh "$ROOT/setup.sh" 2>/dev/null || true)"
assert_empty "変数直後にマルチバイト文字が続く箇所が無い（\${VAR} を使う）" "$bad"
for f in "$HOOKS"/*.sh "$ROOT/setup.sh"; do bash -n "$f" 2>/dev/null || fail "構文: $f"; done
ok "全 hook が bash -n を通る"

# ---------------------------------------------------------------------------
# pre-agent-check.sh
# ---------------------------------------------------------------------------
section "pre-agent-check.sh"
dir="$(new_project)"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json some-other-agent)")"
assert_empty "stage-*-agent 以外は素通り" "$out"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-requirements-agent opus)")"
assert_empty "requirements は state.json 無しでも許可" "$out"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
assert_eq "state.json 無しで stage-spec-agent は deny" "$(decision "$out")" "deny"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-requirements-agent opus plan)")"
assert_eq "プランモードでは requirements でも deny" "$(decision "$out")" "deny"
assert_contains "プランモード deny の理由" "$(reason "$out")" "プランモード"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json some-other-agent haiku plan)")"
assert_empty "プランモードでも stage-*-agent 以外は素通り" "$out"

printf '{broken' > "$dir/doc/process/state.json"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
assert_eq "state.json 不正 JSON は deny" "$(decision "$out")" "deny"

write_state "$dir" spec
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
assert_empty "next_stage=spec + stage-spec-agent は許可（出力なし）" "$out"
assert_contains "agent_start が flow.log に記録される" "$(cat "$dir/doc/process/flow.log")" "event=agent_start agent=stage-spec-agent stage=spec"

out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-test-agent)")"
assert_eq "ステージとエージェントの不一致は ask" "$(decision "$out")" "ask"
assert_contains "不一致理由に期待エージェント名" "$(reason "$out")" "stage-spec-agent"

write_state "$dir" spec '.agent_hierarchy.current_depth = 4'
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
assert_eq "階層深さ上限で ask" "$(decision "$out")" "ask"

write_state "$dir" spec '.harness.stage_history = [range(5) | {stage:"spec"}]'
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
assert_eq "同一ステージ 5 回で ask（ループ検出）" "$(decision "$out")" "ask"

rm -f "$dir/doc/process/state.json"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-bootstrap-agent opus)")"
assert_empty "bootstrap は state.json 無しで許可" "$out"
write_state "$dir" spec
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-bootstrap-agent opus)")"
assert_eq "進行中 run があるときの bootstrap は ask" "$(decision "$out")" "ask"
write_state "$dir" completed
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-bootstrap-agent opus)")"
assert_empty "completed なら bootstrap は許可" "$out"

printf '{"current_phase":"phase_2","mode":"full"}' > "$dir/doc/process/state.json"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
assert_empty "旧スキーマ current_phase=phase_2 は next_stage=spec として許可" "$out"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-test-agent)")"
assert_eq "旧スキーマでも不一致は ask" "$(decision "$out")" "ask"

HOME_BAK="$HOME"; export HOME="$(mktemp -d)"
out="$(run_hook pre-agent-check.sh "$dir" "$(agent_json stage-spec-agent)")"
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

write_state "$dir" implementation
write_checklist "$dir"
out="$(run_hook state-sync.sh "$dir" "$(write_json "$dir/doc/process/state.json")")"
assert_eq "正常な state.json は exit 0" "$(hook_rc)" "0"
assert_contains "additionalContext に次ステージ" "$(reason "$out")" "Stage 4/6 implementation: 並列実装"
cl="$(cat "$dir/doc/process/task_checklist.md")"
assert_contains "requirements が [x] に同期" "$cl" "- [x] 1. requirements"
assert_contains "consistency が [x] に同期" "$cl" "- [x] 3. consistency"
assert_contains "implementation は [ ] のまま" "$cl" "- [ ] 4. implementation"
assert_contains "ステージ進捗以外のチェックボックスは触らない" "$cl" "- [ ] TASK-001"
assert_contains "stage_transition が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=stage_transition stage=implementation"

# 巻き戻し（--from=spec 相当）
write_state "$dir" spec
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/state.json)")"
cl="$(cat "$dir/doc/process/task_checklist.md")"
assert_contains "巻き戻しで spec が [ ] に戻る" "$cl" "- [ ] 2. spec"
assert_contains "巻き戻しでも requirements は [x]" "$cl" "- [x] 1. requirements"

# escalation
printf '# エスカレーション報告: test\n' > "$dir/doc/process/escalation_test_20260921.md"
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/escalation_test_20260921.md)")"
assert_eq "escalation 書き込みは exit 0" "$(hook_rc)" "0"
assert_contains "escalation が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=escalation file=escalation_test_20260921.md"

# state.json の値域
write_state "$dir" bogus_stage
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/state.json)")"
assert_eq "next_stage の値域外は exit 2" "$(hook_rc)" "2"
write_state "$dir" spec '.kind = "hotfix"'
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/state.json)")"
assert_eq "kind の値域外は exit 2" "$(hook_rc)" "2"
write_state "$dir" spec '.kind = "fix"'
out="$(run_hook state-sync.sh "$dir" "$(write_json doc/process/state.json)")"
assert_eq "正しい next_stage / kind は exit 0" "$(hook_rc)" "0"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# doc-validate.sh / doc-validate.py
# ---------------------------------------------------------------------------
section "doc-validate.sh / doc-validate.py"
SAMPLE="$ROOT/evals/fixtures/sample-project"
dir="$(new_project)"; cp -R "$SAMPLE/." "$dir/"

out="$(run_hook doc-validate.sh "$dir" "$(write_json src/main.go)")"
assert_empty "doc/ 以外の書き込みは素通り" "$out"

out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/test-spec/auth.md)")"
assert_eq "正しいテスト定義書は exit 0" "$(hook_rc)" "0"
assert_contains "検証 OK が additionalContext に出る" "$(reason "$out")" "スキーマ検証 OK"

out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/process/task_checklist.md)")"
assert_eq "正しいチェックリストは exit 0" "$(hook_rc)" "0"

# covers に存在しない REQ
sed -i.bak 's/covers: \[REQ-004\]/covers: [REQ-099]/' "$dir/doc/test-spec/auth.md"
out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/test-spec/auth.md)")"
assert_eq "存在しない REQ を covers すると exit 2" "$(hook_rc)" "2"
assert_contains "違反理由が stderr に出る" "$(hook_err)" "REQ-099 が doc/requirements/ に存在しません"
cp "$SAMPLE/doc/test-spec/auth.md" "$dir/doc/test-spec/auth.md"

# implemented_by の関数が無い
sed -i.bak 's/TestLogin_WrongPassword$/TestLogin_Missing/' "$dir/doc/test-spec/auth.md"
out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/test-spec/auth.md)")"
assert_eq "implemented_by の関数が無ければ exit 2" "$(hook_rc)" "2"
cp "$SAMPLE/doc/test-spec/auth.md" "$dir/doc/test-spec/auth.md"

# frontmatter なし
printf '# API\n本文のみ\n' > "$dir/doc/api-spec/x.md"
out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/api-spec/x.md)")"
assert_eq "frontmatter 無しは exit 2" "$(hook_rc)" "2"
assert_contains "doc_invalid が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=doc_invalid file=doc/api-spec/x.md"

# ID 重複（requirements）
sed -i.bak 's/  - id: REQ-005/  - id: REQ-004/' "$dir/doc/requirements/auth.md"
out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/requirements/auth.md)")"
assert_eq "REQ の重複は exit 2" "$(hook_rc)" "2"
assert_contains "重複の理由" "$(hook_err)" "REQ-004: ID が重複しています"

# 旧形式のチェックリスト
printf '# x\n\n## フェーズ進捗\n- [ ] Phase 1-2\n' > "$dir/doc/process/task_checklist.md"
out="$(run_hook doc-validate.sh "$dir" "$(write_json doc/process/task_checklist.md)")"
assert_eq "旧形式のチェックリストは exit 2" "$(hook_rc)" "2"

# --all（eval 用の入口）
out="$(cd "$SAMPLE" && python3 "$HOOKS/doc-validate.py" --all)"
assert_contains "--all でサンプルプロジェクトが通る" "$out" "summary: 0 errors"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# agent-complete.sh
# ---------------------------------------------------------------------------
section "agent-complete.sh"
dir="$(new_project)"
write_state "$dir" spec

out="$(run_hook agent-complete.sh "$dir" "$(agent_json some-other-agent)")"
assert_empty "stage-*-agent 以外は素通り" "$out"

# agent_start を 90 秒前に偽装（log_flow と同じ書式）
ts="$(TZ=Asia/Tokyo date '+%Y-%m-%dT%H:%M:%S%z')"
(
  source "$HOOKS/lib.sh" </dev/null
  past="$(( $(iso_to_epoch "$ts") - 90 ))"
  # epoch → ISO（GNU / BSD）
  iso="$(TZ=Asia/Tokyo date -d "@$past" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || TZ=Asia/Tokyo date -j -r "$past" '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s event=agent_start agent=stage-requirements-agent stage=requirements model=opus\n' "$iso" > "$dir/doc/process/flow.log"
)
out="$(run_hook agent-complete.sh "$dir" "$(agent_json stage-requirements-agent opus)")"
assert_contains "完了が flow.log に記録" "$(cat "$dir/doc/process/flow.log")" "event=agent_complete agent=stage-requirements-agent"
dur="$(grep -o 'duration_seconds=[0-9]*' "$dir/doc/process/flow.log" | cut -d= -f2)"
[ -n "$dur" ] && [ "$dur" -ge 89 ] && [ "$dur" -le 95 ] && ok "所要時間が算出される（GNU/BSD date）" || fail "所要時間" "got: ${dur:-empty}"
assert_contains "requirements 完了時は人間確認ゲートを念押し" "$(reason "$out")" "人間確認ゲート"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# session-start.sh / stop-summary.sh
# ---------------------------------------------------------------------------
section "session-start.sh / stop-summary.sh"
dir="$(new_project)"

out="$(run_hook session-start.sh "$dir" '{}')"
assert_empty "state.json 無しは何も出さない" "$out"

write_state "$dir" implementation '.implementation_progress = {completed_groups:["group-1"], pr_numbers:{"group-1":[101],"group-2":[102]}, base_branch:"feature/xxx"}'
out="$(run_hook session-start.sh "$dir" '{}')"
assert_contains "次ステージを表示" "$out" "next_stage=implementation"
assert_contains "マージ待ち PR を表示（完了グループは除外）" "$out" "group-2: PR #102"
assert_not_contains "完了グループの PR は表示しない" "$out" "group-1: PR #101"

out="$(run_hook stop-summary.sh "$dir" '{}')"
assert_empty "flow.log が無ければ stop-summary は沈黙" "$out"
printf '%s event=stage_transition stage=implementation\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$dir/doc/process/flow.log"
out="$(run_hook stop-summary.sh "$dir" '{}')"
assert_contains "直近イベントがあれば systemMessage を出す（file_mtime）" "$(printf '%s' "$out" | jq -r '.systemMessage')" "Stage 4/6 implementation: 並列実装"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# pr-merge-guard.sh
# ---------------------------------------------------------------------------
section "pr-merge-guard.sh（gh はスタブ）"
dir="$(new_project)"
write_state "$dir" implementation '.implementation_progress = {base_branch:"feature/xxx"}'

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json 'git status')")"
assert_empty "gh pr merge を含まないコマンドは素通り" "$out"

M="gh pr merge"
out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json "cat > note.md <<'EOF'
手順: $M 123 --merge を実行する
EOF
echo done")")"
assert_empty "heredoc 本文に含まれる gh pr merge は素通り（誤検知しない）" "$out"

out="$(run_hook pr-merge-guard.sh "$dir" "$(bash_json "python3 - <<EOF
print('$M は禁止')
EOF
$M 102 --merge")")"
assert_eq "heredoc の後に本物の gh pr merge があれば検査する" "$(decision "$out")" "deny"

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
