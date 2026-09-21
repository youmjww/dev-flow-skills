#!/bin/bash
# test-spec-writer の eval。fixture の要件定義書に対して writer プロンプトを claude -p で実行し、
# 出力を evals/lib/score-test-spec.py で機械的に採点する。
#
# 使い方:
#   bash evals/run-spec-eval.sh [--scenario feature|change|all] [--model sonnet|haiku|opus] [--keep] [--runs N]
#
# シナリオ:
#   feature : 要件定義書だけがある状態から全文生成（既定）
#   change  : 既存のテスト定義書があり、REQ-003 が modified・REQ-006 が added の差分更新。既存 ID の保持を採点
#
# 前提: claude CLI にログイン済み。1 シナリオあたり数分・数万トークンを消費する。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO=feature
MODEL=sonnet
KEEP=false
RUNS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --scenario) SCENARIO="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --keep) KEEP=true; shift ;;
    --runs) RUNS="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "不明なオプション: $1" >&2; exit 2 ;;
  esac
done
command -v claude >/dev/null 2>&1 || { echo "claude CLI が見つかりません" >&2; exit 2; }

PROMPT_FILE="$ROOT/dev-flow-spec/prompts/test-spec-writer.md"
SAMPLE="$ROOT/evals/fixtures/sample-project"
RESULTS_DIR="$ROOT/evals/results"
mkdir -p "$RESULTS_DIR"

render_prompt() { # <kind> <changed> <fix>
  python3 - "$PROMPT_FILE" "$1" "$2" "$3" <<'PY'
import sys
path, kind, changed, fix = sys.argv[1:5]
s = open(path, encoding="utf-8").read()
s = s.replace("{REQUIREMENTS_PATHS}", "- doc/requirements/auth.md")
s = s.replace("{TEST_SPEC_PATH}", "doc/test-spec/auth.md")
s = s.replace("{KIND}", kind).replace("{CHANGED_REQ_IDS}", changed).replace("{FIX_DESCRIPTION}", fix)
s = s.replace("{同名}", "auth")
print("作業ディレクトリはカレントディレクトリです。相対パスはそのまま使ってください。SendMessage は使えません。\n\n" + s)
PY
}

run_one() { # <scenario> <run_no>
  local scenario="$1" n="$2" work kind changed baseline
  work="$(mktemp -d "${TMPDIR:-/tmp}/dev-flow-eval.XXXXXX")"
  mkdir -p "$work/doc/requirements" "$work/doc/test-spec"
  case "$scenario" in
    feature)
      cp "$SAMPLE/doc/requirements/auth.md" "$work/doc/requirements/"
      kind=feature; changed=""; baseline="" ;;
    change)
      cp "$ROOT/evals/fixtures/change-scenario/auth.md" "$work/doc/requirements/"
      cp "$SAMPLE/doc/test-spec/auth.md" "$work/doc/test-spec/"
      # implemented_by は fixture のコードを指すので、コードも置く
      mkdir -p "$work/pkg/auth" && cp "$SAMPLE/pkg/auth/login_test.go" "$work/pkg/auth/"
      kind=change; changed="REQ-003 (modified), REQ-006 (added)"; baseline="$SAMPLE/doc/test-spec/auth.md" ;;
    *) echo "不明なシナリオ: $scenario" >&2; return 2 ;;
  esac
  (cd "$work" && git init -q && git add -A && git commit -qm "fixture")

  local stamp; stamp="$(date +%Y%m%d%H%M%S)"
  local log="$RESULTS_DIR/${scenario}-${MODEL}-${stamp}-${n}.log"
  echo "▶ $scenario run $n (model=$MODEL) work=$work"
  render_prompt "$kind" "$changed" "" > "$work/.prompt.md"
  local t0; t0="$(date +%s)"
  (cd "$work" && claude -p "$(cat .prompt.md)" \
      --model "$MODEL" \
      --permission-mode acceptEdits \
      --allowedTools "Read,Write,Edit,Bash,Grep,Glob" \
      --output-format text) > "$log" 2>&1
  local rc=$? t1; t1="$(date +%s)"
  echo "  claude 終了: rc=$rc, $((t1 - t0)) 秒, ログ: $log"

  local score_args=(--project-dir "$work" --scenario "$scenario")
  [ -n "$baseline" ] && score_args+=(--baseline-spec "$baseline" --changed "REQ-003:modified,REQ-006:added")
  python3 "$ROOT/evals/lib/score-test-spec.py" "${score_args[@]}" | tee -a "$log" | grep -v '^{'
  local srC=${PIPESTATUS[0]}
  tail -1 "$log" | python3 -c "import json,sys; j=json.load(sys.stdin); print(f'  → score={j[\"score\"]} must={j[\"must_pass\"]}/{j[\"must_total\"]}')"
  if [ "$KEEP" = true ]; then echo "  出力を保持: $work"; else rm -rf "$work"; fi
  return "$srC"
}

fail=0
for s in $( [ "$SCENARIO" = all ] && echo "feature change" || echo "$SCENARIO" ); do
  for n in $(seq 1 "$RUNS"); do
    run_one "$s" "$n" || fail=$((fail + 1))
  done
done
echo
[ "$fail" -eq 0 ] && echo "eval: すべて PASS" || echo "eval: $fail 件 FAIL"
exit "$fail"
