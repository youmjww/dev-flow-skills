#!/usr/bin/env python3
"""テストコードの静的検証（Go / Python / TypeScript・JavaScript / PHP / シェル）。

conventions/testing.md のルールのうち、ソースを読むだけで判定できるものを機械化する。
判断が要るもの（分岐網羅・SUT モック・独立性）は reviewer に残す。

使い方:
  test-lint.py FILE...        # 指定ファイルを検証
  test-lint.py --all [DIR]    # DIR（既定: カレント）配下のテストファイルをすべて検証
終了コード: 0 = error なし（warn は許容）, 1 = error あり, 2 = 使い方の誤り
出力: 1 行 1 件 "ERROR|WARN <file>:<line> <rule>: <message>"、最後に "summary: N errors, M warnings"

ルール（severity）:
  test/no-skip           error  スキップ・無効化（t.Skip / it.skip / xit / @pytest.mark.skip / markTestSkipped ...）
  test/assert-present    error  assert の無いテスト関数
  test/empty-test        error  本体が空（またはコメントのみ）のテスト関数
  test/swallowed-error   error  テスト内で例外・エラーを握りつぶしている（except: pass / catch {} / _ = err）
  test/zero-assertions   error  expect.assertions(0) / expect.hasAssertions を無効化
  test/commented-out     warn   コメントアウトされたテスト
  test/deterministic     warn   sleep / 現在時刻 / 乱数 / 実 URL への依存
  test/tautology         warn   期待値を SUT と同じ呼び出しで作っている
  test/no-tests          warn   テスト関数が 1 つも無い
  test/ts-ignore         warn   テスト内の @ts-ignore / as any

シェル（*.bats / *_test.sh / test_*.sh / tests/ 配下の *.sh。インフラの結合テスト）:
  test/no-skip           error  bats の skip
  test/self-compare      error  [ "$x" = "$x" ] のように同じ値どうしを比較している（常に真）
  test/assert-present    error  assert の無い bats の @test
  test/empty-test        error  本体が空の bats の @test
  test/grep-count-lines  warn   grep -c は「一致した行数」。1 行に複数回出る値の出現回数なら grep -o … | wc -l
  test/restore-trap      warn   設定・サービスを壊す操作があるのに trap … EXIT で復元していない
  test/restore-warn-only warn   失敗を `|| echo WARN` で流している（復元・検証の失敗がテスト失敗にならない）
  test/ipv4-only         warn   IPv4 だけを前提にしたアドレス照合（::ffff:192.0.2.1 の IPv4 射影 IPv6 を取りこぼす）
  test/deterministic     warn   固定秒数の sleep
"""
import glob
import os
import re
import sys

TEST_FILE_RE = re.compile(
    r"(_test\.go|_test\.py|(^|/)test_[^/]*\.py|\.(test|spec)\.(ts|tsx|js|jsx)|Test\.php|_spec\.rb|\.bats|_test\.sh|(^|/)test_[^/]*\.sh)$"
)
TEST_DIR_RE = re.compile(r"(^|/)(tests?|__tests__|spec|e2e)/")


def language_of(path):
    if path.endswith(".go"):
        return "go"
    if path.endswith(".py"):
        return "py"
    if re.search(r"\.(ts|tsx|js|jsx|mjs|cjs)$", path):
        return "ts"
    if path.endswith(".php"):
        return "php"
    if path.endswith((".sh", ".bats")):
        return "sh"
    return None


def is_test_path(path):
    p = path.replace("\\", "/")
    return bool(TEST_FILE_RE.search(p)) or (bool(TEST_DIR_RE.search(p)) and language_of(p) is not None)


# ---------------------------------------------------------------------------
# 言語ごとの定義
# ---------------------------------------------------------------------------
LANG = {
    "go": {
        "test_def": re.compile(r"^\s*func\s+(Test\w*)\s*\(\s*\w+\s+\*testing\.(T|M)\s*\)"),
        "subtest": re.compile(r"\bt\.Run\s*\("),
        "assert": re.compile(r"\b(t|tb|tt)\.(Error|Errorf|Fatal|Fatalf|Fail|FailNow)\b|\b(assert|require|is|cmp|gomega|Expect|Ω)\b|\bt\.Helper\(\)\s*$|\bif\s+.*\{\s*$"),
        "assert_strict": re.compile(r"\b(t|tb|tt)\.(Error|Errorf|Fatal|Fatalf|Fail|FailNow)\b|\b(assert|require|is)\.\w+\(|\bcmp\.Diff\(|\bExpect\(|\bΩ\("),
        "skip": re.compile(r"\b(t|tb|tt)\.(Skip|Skipf|SkipNow)\s*\("),
        "sleep": re.compile(r"\btime\.Sleep\s*\("),
        "now": re.compile(r"\btime\.Now\s*\(\)"),
        "random": re.compile(r"\b(rand\.(Int|Intn|Float64|Read)|uuid\.New)\s*\("),
        "swallow": re.compile(r"^\s*_\s*=\s*err\b|^\s*_\s*,\s*_\s*=\s*\w"),
        "comment": "//",
        "commented_test": re.compile(r"^\s*//\s*func\s+Test\w*\s*\("),
        "call": re.compile(r"(\w+(?:\.\w+)*\((?:[^()]|\([^()]*\))*\))"),
        "assign": re.compile(r"^\s*(\w+)\s*:?=\s*(\w+(?:\.\w+)*\((?:[^()]|\([^()]*\))*\))\s*$"),
    },
    "py": {
        "test_def": re.compile(r"^\s*(async\s+)?def\s+(test\w*)\s*\("),
        "subtest": re.compile(r"\bsubTest\s*\("),
        "assert": re.compile(r"^\s*assert\b|\bpytest\.raises\s*\(|\bself\.assert\w*\(|\bassert_\w+\(|\.assert_called|\bassertpy\b|\bexpect\(", re.M),
        "assert_strict": None,
        "skip": re.compile(r"@pytest\.mark\.(skip|skipif|xfail)|\bpytest\.skip\s*\(|@unittest\.skip|\bself\.skipTest\s*\("),
        "sleep": re.compile(r"\btime\.sleep\s*\(|\basyncio\.sleep\s*\((?!0\))"),
        "now": re.compile(r"\bdatetime\.(now|utcnow|today)\s*\(|\bdate\.today\s*\(|\btime\.time\s*\("),
        "random": re.compile(r"\brandom\.\w+\s*\(|\buuid\.uuid4\s*\("),
        "swallow": re.compile(r"^\s*except\b[^:]*:\s*(pass|\.\.\.)?\s*$"),
        "comment": "#",
        "commented_test": re.compile(r"^\s*#\s*(async\s+)?def\s+test\w*\s*\("),
        "call": re.compile(r"(\w+(?:\.\w+)*\((?:[^()]|\([^()]*\))*\))"),
        "assign": re.compile(r"^\s*(\w+)\s*=\s*(\w+(?:\.\w+)*\((?:[^()]|\([^()]*\))*\))\s*$"),
    },
    "ts": {
        "test_def": re.compile(r"^\s*(it|test)(\.only|\.each\([^)]*\))?\s*\(\s*(['\"`])(.*?)\3"),
        "subtest": None,
        "assert": re.compile(r"\bexpect(TypeOf)?\s*\(|\bassert(\.\w+)?\s*\(|\bshould\b|\.toMatchSnapshot\(|\bexpect\.assertions\("),
        "assert_strict": None,
        "skip": re.compile(r"\b(it|test|describe)\.(skip|todo)\s*\(|\b(xit|xtest|xdescribe)\s*\("),
        "sleep": re.compile(r"new Promise\s*\(\s*(resolve|r)\s*=>\s*setTimeout|\bawait\s+sleep\s*\(|\bawait\s+delay\s*\(|\bawait\s+wait\s*\(\s*\d"),
        "now": re.compile(r"\bDate\.now\s*\(\)|\bnew Date\s*\(\s*\)"),
        "random": re.compile(r"\bMath\.random\s*\(|\bcrypto\.randomUUID\s*\(|\buuidv4\s*\(|\bnanoid\s*\("),
        "swallow": re.compile(r"\bcatch\s*(\(\s*\w*\s*\))?\s*\{\s*\}"),
        "comment": "//",
        "commented_test": re.compile(r"^\s*//\s*(it|test)\s*\(\s*['\"`]"),
        "call": re.compile(r"(\w+(?:\.\w+)*\((?:[^()]|\([^()]*\))*\))"),
        "assign": re.compile(r"^\s*(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(\w+(?:\.\w+)*\((?:[^()]|\([^()]*\))*\))\s*;?\s*$"),
        "zero_assertions": re.compile(r"\bexpect\.assertions\s*\(\s*0\s*\)"),
        "ts_ignore": re.compile(r"@ts-ignore|\bas any\b"),
    },
    "php": {
        "test_def": re.compile(r"^\s*(public\s+)?function\s+(test\w*)\s*\(|^\s*(it|test)\s*\(\s*['\"](.*?)['\"]"),
        "subtest": None,
        "assert": re.compile(r"\$this->assert\w*\(|\bself::assert\w*\(|\bexpect\s*\(|\$this->expectException|->assert\w+\(|\bassertDatabase\w*\("),
        "assert_strict": None,
        "skip": re.compile(r"->markTestSkipped\s*\(|->markTestIncomplete\s*\(|#\[(Skip|Incomplete)\]|->skip\s*\("),
        "sleep": re.compile(r"\b(sleep|usleep)\s*\("),
        "now": re.compile(r"\bnew\s+DateTime(Immutable)?\s*\(\s*\)|\bnow\s*\(\s*\)|\bCarbon::now\s*\(|\btime\s*\(\s*\)|\bdate\s*\("),
        "random": re.compile(r"\b(rand|mt_rand|random_int)\s*\(|Str::random\s*\(|Str::uuid\s*\("),
        "swallow": re.compile(r"\bcatch\s*\([^)]*\)\s*\{\s*\}"),
        "comment": "//",
        "commented_test": re.compile(r"^\s*//\s*(public\s+)?function\s+test\w*\s*\("),
        "call": re.compile(r"(\$?\w+(?:->\w+|::\w+)*\((?:[^()]|\([^()]*\))*\))"),
        "assign": re.compile(r"^\s*\$(\w+)\s*=\s*(\$?\w+(?:->\w+|::\w+)*\((?:[^()]|\([^()]*\))*\))\s*;\s*$"),
    },
}

# time.Now 等を許容する文脈（テスト用の時計を設定している行）
NOW_ALLOW = re.compile(r"setTestNow|freeze|travel|FakeClock|fakeClock|MockClock|useFakeTimers|setSystemTime|freezegun|time_machine|clockwork")


class Report:
    def __init__(self):
        self.items = []

    def add(self, sev, f, line, rule, msg):
        self.items.append((sev, f, line, rule, msg))

    @property
    def errors(self):
        return [i for i in self.items if i[0] == "ERROR"]

    @property
    def warnings(self):
        return [i for i in self.items if i[0] == "WARN"]


def strip_comment(line, marker):
    # 文字列内の // は雑に扱うが、テストコードの検証用途では十分
    i = line.find(marker)
    return line[:i] if i >= 0 else line


def split_tests(lines, lang):
    """テスト関数ごとに (名前, 開始行, 終了行) を返す（ブレース / インデントで大雑把に区切る）。"""
    L = LANG[lang]
    tests = []
    starts = [(i, m) for i, l in enumerate(lines) if (m := L["test_def"].match(l))]
    for k, (i, m) in enumerate(starts):
        if lang == "ts":
            name = m.group(4) or "test"
        elif lang == "php":
            name = m.group(2) or m.group(4) or "test"
        else:
            name = next((g for g in m.groups() if g and g.strip() not in ("async", "public", "T", "M")), "test")
        if lang == "py":
            base = len(lines[i]) - len(lines[i].lstrip())
            end = len(lines)
            for j in range(i + 1, len(lines)):
                l = lines[j]
                if l.strip() and (len(l) - len(l.lstrip())) <= base and not l.lstrip().startswith(("#", "@")):
                    end = j
                    break
        else:
            depth = 0
            end = len(lines)
            opened = False
            for j in range(i, len(lines)):
                depth += lines[j].count("{") - lines[j].count("}")
                if "{" in lines[j]:
                    opened = True
                if opened and depth <= 0:
                    end = j + 1
                    break
        # 次のテスト定義より前で切る
        if k + 1 < len(starts):
            end = min(end, starts[k + 1][0])
        tests.append((name, i, end))
    return tests


# ---------------------------------------------------------------------------
# シェル（インフラの結合テスト）
# ---------------------------------------------------------------------------
SH = {
    "test_def": re.compile(r"^\s*@test\s+(['\"])(.*?)\1\s*\{"),
    "skip": re.compile(r"^\s*skip\b"),
    # [ "$a" = "$a" ] / [[ $a == $a ]] / test "$a" -eq "$a"
    "self_compare": re.compile(r"(?:\[\[?|\btest)\s+(\"?\$\{?\w+\}?\"?)\s*(?:==?|!=|-eq|-ne|-ge|-le)\s*(\"?\$\{?\w+\}?\"?)\s*(?:\]\]?|$|;|&&|\|\|)"),
    "grep_count": re.compile(r"\bgrep\b[^|;]*\s-(?:\w*c\w*)\b|\bgrep\b[^|;]*--count\b"),
    # 状態を壊す操作（復元が要る）
    "destructive": re.compile(r"\bsystemctl\s+(stop|disable|mask|kill)\b|\bsed\s+-i\b|\bmv\s+\S*/etc/|\bcp\s+\S+\s+/etc/|\biptables\s+-[AIDF]\b|\bnft\s+(add|delete|flush)\b|\bip\s+link\s+set\s+\S+\s+down\b|\bkill(all)?\s|\bpct\s+(stop|set)\b|\bqm\s+(stop|set)\b"),
    "trap": re.compile(r"^\s*trap\s+.+\b(EXIT|ERR|INT|TERM)\b"),
    "bats_teardown": re.compile(r"^\s*teardown(_file)?\s*\(\)"),
    "warn_only": re.compile(r"\|\|\s*(echo|printf)\b[^;&|]*\b(WARN|warn|Warning|警告)"),
    "ipv4_regex": re.compile(r"(\[0-9\]|\\d)(\{1,3\}|\+)\\\.(\[0-9\]|\\d)"),
    "ipv6_aware": re.compile(r"::ffff:|ffff|ipv6|IPv6|inet6|-6\b"),
    "sleep": re.compile(r"^\s*sleep\s+\d"),
    "assert": re.compile(r"\[\[?\s|\btest\s|\bassert\w*\b|\brefute\w*\b|\bgrep\s+(-\w*q|--quiet)|\bfail\b|\bexit\s+1\b|\breturn\s+1\b|\bdiff\s|\bcmp\s|\(\(.*[<>=]"),
}


def strip_sh_comment(line):
    s = line.lstrip()
    return "" if s.startswith("#") and not s.startswith("#!") else line


def lint_shell(path, lines, rep):
    code = [strip_sh_comment(l) for l in lines]
    full = "\n".join(code)
    has_trap = any(SH["trap"].match(l) for l in code) or any(SH["bats_teardown"].match(l) for l in code)
    ipv6_aware = bool(SH["ipv6_aware"].search(full))
    destructive_reported = False
    for i, l in enumerate(code, 1):
        if not l.strip():
            continue
        if path.endswith(".bats") and SH["skip"].match(l):
            rep.add("ERROR", path, i, "test/no-skip", "テストのスキップ。通らないならプロダクション側を直すかエスカレーションする")
        m = SH["self_compare"].search(l)
        if m and m.group(1).strip('"') == m.group(2).strip('"'):
            rep.add("ERROR", path, i, "test/self-compare", f"{m.group(1)} を自分自身と比較している（常に真）。期待値はテスト定義書のリテラルにする")
        if SH["grep_count"].search(l):
            rep.add("WARN", path, i, "test/grep-count-lines", "grep -c は一致した「行数」を返す。1 行に複数回出る値の出現回数を数えるなら grep -o PATTERN | wc -l")
        if SH["warn_only"].search(l):
            rep.add("WARN", path, i, "test/restore-warn-only", "失敗を WARN 表示だけで流している。復元・検証の失敗はテスト失敗（exit 1）にする")
        if SH["ipv4_regex"].search(l) and not ipv6_aware:
            rep.add("WARN", path, i, "test/ipv4-only", "IPv4 だけを前提にしたアドレス照合。::ffff:192.0.2.1 形式（IPv4 射影 IPv6）で来る値を取りこぼさないか確認する")
        if SH["sleep"].match(l):
            rep.add("WARN", path, i, "test/deterministic", "固定秒数の sleep。状態をポーリングして待つ（until …; do sleep 1; done に上限を付ける）")
        if not destructive_reported and not has_trap and SH["destructive"].search(l):
            rep.add("WARN", path, i, "test/restore-trap", "設定・サービスを変更する操作があるのに trap '…' EXIT（bats は teardown）で復元していない。途中で失敗すると環境が壊れたまま残る")
            destructive_reported = True

    # bats の @test ごとのルール（素のシェルスクリプトは関数の区切りが無いのでファイル単位のルールのみ）
    if not path.endswith(".bats"):
        return
    starts = [(i, m.group(2)) for i, l in enumerate(lines) if (m := SH["test_def"].match(l))]
    if not starts:
        rep.add("WARN", path, 1, "test/no-tests", "@test が見つからない")
        return
    for k, (i, name) in enumerate(starts):
        depth, end = 0, len(lines)
        for j in range(i, len(lines)):
            depth += lines[j].count("{") - lines[j].count("}")
            if depth <= 0:
                end = j
                break
        if k + 1 < len(starts):
            end = min(end, starts[k + 1][0])
        body = [l for l in code[i + 1:end] if l.strip() and l.strip() != "}"]
        if not body:
            rep.add("ERROR", path, i + 1, "test/empty-test", f"{name}: 本体が空")
            continue
        joined = "\n".join(body)
        if SH["skip"].search(joined):
            continue
        if not SH["assert"].search(joined):
            rep.add("ERROR", path, i + 1, "test/assert-present", f"{name}: assert が無い（結果を検証していない）")


def lint_file(path, rep):
    lang = language_of(path)
    if lang is None:
        return
    if lang == "sh":
        with open(path, encoding="utf-8", errors="replace") as fh:
            lint_shell(path, fh.read().split("\n"), rep)
        return
    L = LANG[lang]
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    rel = path

    # ファイル全体のルール
    for i, raw in enumerate(lines, 1):
        code = strip_comment(raw, L["comment"]) if lang != "py" else strip_comment(raw, "#")
        if L["skip"].search(code):
            rep.add("ERROR", rel, i, "test/no-skip", "テストのスキップ・無効化。通らないならプロダクションコードを直すかエスカレーションする")
        if L["commented_test"].match(raw):
            rep.add("WARN", rel, i, "test/commented-out", "コメントアウトされたテスト。不要なら削除を人間に確認、必要なら復活させる")
        if L["swallow"].search(code):
            rep.add("ERROR", rel, i, "test/swallowed-error", "テスト内で例外・エラーを握りつぶしている。失敗を検出できない")
        if L["sleep"].search(code):
            rep.add("WARN", rel, i, "test/deterministic", "sleep でタイミングを合わせている。完了待ち（waitFor / Eventually / channel）に置き換える")
        if L["now"].search(code) and not NOW_ALLOW.search(code):
            rep.add("WARN", rel, i, "test/deterministic", "テストが現在時刻に依存している。時計を固定（setTestNow / useFakeTimers / 注入）する")
        if L["random"].search(code):
            rep.add("WARN", rel, i, "test/deterministic", "テストが乱数に依存している。固定値かシード付きにする")
        if re.search(r"https?://(?!localhost|127\.0\.0\.1|example\.(com|org)|test\b)[\w.-]+", code):
            rep.add("WARN", rel, i, "test/deterministic", "実 URL への依存。境界でフェイクする（httptest / Http::fake / msw）")
        if lang == "ts":
            if L["zero_assertions"].search(code):
                rep.add("ERROR", rel, i, "test/zero-assertions", "expect.assertions(0) はテストを無効化する")
            if L["ts_ignore"].search(code):
                rep.add("WARN", rel, i, "test/ts-ignore", "テスト内の @ts-ignore / as any。型の抜け穴でバグを隠す")

    # テスト関数ごとのルール
    tests = split_tests(lines, lang)
    if not tests:
        rep.add("WARN", rel, 1, "test/no-tests", "テスト関数が見つからない")
        return
    for name, start, end in tests:
        body = lines[start + 1:end]
        code_lines = [strip_comment(l, L["comment"]) for l in body]
        nonblank = [l for l in code_lines if l.strip() and l.strip() not in ("}", "})", "});", "});", "{")]
        if not nonblank:
            rep.add("ERROR", rel, start + 1, "test/empty-test", f"{name}: 本体が空")
            continue
        joined = "\n".join(code_lines)
        if L["skip"].search(joined):
            continue  # スキップは test/no-skip で報告済み。assert の有無は見ない
        has_assert = bool(L["assert"].search(joined))
        # Go: t.Run のサブテストがあり、その中に assert があれば OK。`if ... { t.Errorf }` 型は assert_strict で拾う
        if lang == "go" and not L["assert_strict"].search(joined):
            has_assert = False
        if not has_assert:
            rep.add("ERROR", rel, start + 1, "test/assert-present", f"{name}: assert が無い（結果を検証していない）")

        # tautology: expected := f(x) と同じ呼び出しが assert 行にある
        for j, l in enumerate(code_lines):
            m = L["assign"].match(l)
            if not m:
                continue
            var, call = m.group(1), m.group(2)
            if re.match(r"^(new|make|len|append|strings|fmt|json|os|filepath|require|assert|expect|jest|vi|sinon|mock|Mock|faker|Factory|factory|\$this|self|t|tb)\b", call):
                continue
            # 同じ呼び出しが後続に再び現れ（別変数への代入 or assert 行）、かつ var が比較に使われていれば tautology
            rest = "\n".join(code_lines[j + 1:])
            if call in rest and re.search(r"\b" + re.escape(var) + r"\b", rest) and L["assert"].search(rest):
                rep.add("WARN", rel, start + 1 + j + 1, "test/tautology", f"{name}: 期待値 {var} を SUT と同じ呼び出し {call[:40]} で作っている。リテラルで書く")


def main(argv):
    args = argv[1:]
    if not args:
        print(__doc__)
        return 2
    files = []
    if args[0] == "--all":
        root = args[1] if len(args) > 1 else os.getcwd()
        for p in glob.glob(os.path.join(root, "**", "*"), recursive=True):
            rel = os.path.relpath(p, root)
            if os.path.isfile(p) and is_test_path(rel) and not re.search(r"(^|/)(node_modules|vendor|\.git|dist|build)/", rel):
                files.append(p)
        files.sort()
    else:
        files = args
    rep = Report()
    for f in files:
        if not os.path.exists(f):
            rep.add("ERROR", f, 0, "test/no-file", "ファイルがありません")
            continue
        lint_file(f, rep)
    for sev, f, line, rule, msg in rep.items:
        print(f"{sev} {f}:{line} {rule}: {msg}")
    print(f"summary: {len(rep.errors)} errors, {len(rep.warnings)} warnings")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
