#!/usr/bin/env python3
"""dev-flow 成果物のスキーマ検証。

対象: doc/requirements/*.md, doc/test-spec/*.md, doc/api-spec/*.md, doc/infra-spec/*.md,
      doc/process/task_checklist.md
外部依存なし（frontmatter は dev-flow が使う YAML のサブセットだけを解析する）。

使い方:
  doc-validate.py [--project-dir DIR] FILE...      # 指定ファイルを検証
  doc-validate.py [--project-dir DIR] --all        # doc/ 配下の対象をすべて検証
終了コード: 0 = 違反なし（WARN は許容）, 1 = ERROR あり, 2 = 使い方の誤り
出力: 1 行 1 件 "ERROR|WARN <file>: <message>"、最後に "summary: N errors, M warnings"
"""
import argparse
import glob
import os
import re
import sys

ID_PATTERNS = {
    "requirements": ("requirements", r"^REQ-\d{3,}$"),
    "test-spec": ("test_cases", r"^TC-\d{3,}$"),
    "api-spec": ("endpoints", r"^API-\d{3,}$"),
    "infra-spec": ("resources", r"^INFRA-\d{3,}$"),
}
STAGES = ["requirements", "spec", "consistency", "implementation", "test", "compliance"]
STATUS_VALUES = {"added", "modified"}


# ---------------------------------------------------------------------------
# frontmatter パーサ（サブセット: スカラー / インラインリスト / ブロックリスト / 2 段までのマップ）
# ---------------------------------------------------------------------------
def split_frontmatter(text):
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end < 0:
        return None, text
    return text[4:end], text[end + 4:]


def _scalar(s):
    s = s.strip()
    if s.startswith("#"):
        return None
    s = re.sub(r"\s+#.*$", "", s)  # 行末コメント
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        return [] if not inner else [_scalar(x) for x in inner.split(",")]
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    if s in ("true", "false"):
        return s == "true"
    if s in ("null", "~", ""):
        return None
    return s


def parse_yaml_subset(src):
    """dev-flow の frontmatter に必要な範囲の YAML を dict に変換する。"""
    lines = [l.rstrip("\n") for l in src.split("\n")]

    def indent(l):
        return len(l) - len(l.lstrip(" "))

    def parse_block(i, base):
        """i 行目から、インデント base のブロックを解析して (値, 次の行番号) を返す。"""
        # ブロックの種類を先頭の非空行で判定
        j = i
        while j < len(lines) and (not lines[j].strip() or lines[j].strip().startswith("#")):
            j += 1
        if j >= len(lines) or indent(lines[j]) < base:
            return None, j
        if lines[j].lstrip().startswith("- "):
            return parse_list(j, indent(lines[j]))
        return parse_map(j, indent(lines[j]))

    def parse_map(i, base):
        out = {}
        while i < len(lines):
            l = lines[i]
            if not l.strip() or l.strip().startswith("#"):
                i += 1
                continue
            ind = indent(l)
            if ind < base:
                break
            if ind > base or l.lstrip().startswith("- "):
                raise ValueError(f"line {i+1}: unexpected indentation")
            m = re.match(r"^\s*([A-Za-z0-9_.-]+):\s*(.*)$", l)
            if not m:
                raise ValueError(f"line {i+1}: expected 'key: value'")
            key, rest = m.group(1), m.group(2)
            if rest.strip() and not rest.strip().startswith("#"):
                out[key] = _scalar(rest)
                i += 1
            else:
                val, i = parse_block(i + 1, base + 1)
                out[key] = val if val is not None else None
        return out, i

    def parse_list(i, base):
        out = []
        while i < len(lines):
            l = lines[i]
            if not l.strip() or l.strip().startswith("#"):
                i += 1
                continue
            ind = indent(l)
            if ind < base:
                break
            if ind > base or not l.lstrip().startswith("- "):
                raise ValueError(f"line {i+1}: unexpected list item")
            item = l.lstrip()[2:]
            m = re.match(r"^([A-Za-z0-9_.-]+):\s*(.*)$", item)
            if m:
                # リスト要素がマップ: 最初のキーはこの行、続きは base+2 のインデント
                d = {}
                key, rest = m.group(1), m.group(2)
                if rest.strip() and not rest.strip().startswith("#"):
                    d[key] = _scalar(rest)
                    i += 1
                else:
                    val, i = parse_block(i + 1, base + 3)
                    d[key] = val
                more, i = parse_map(i, base + 2) if i < len(lines) and lines[i].strip() and indent(lines[i]) == base + 2 else ({}, i)
                d.update(more)
                out.append(d)
            else:
                out.append(_scalar(item))
                i += 1
        return out, i

    val, _ = parse_block(0, 0)
    return val if isinstance(val, dict) else {}


# ---------------------------------------------------------------------------
# 検証
# ---------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, f, msg):
        self.errors.append(f"ERROR {f}: {msg}")

    def warn(self, f, msg):
        self.warnings.append(f"WARN {f}: {msg}")


def doc_type_of(path):
    parts = path.replace("\\", "/").split("/")
    if "doc" in parts:
        i = parts.index("doc")
        if i + 1 < len(parts):
            return parts[i + 1]
    return None


def load_frontmatter(path, rep, rel):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fm_src, body = split_frontmatter(text)
    if fm_src is None:
        rep.error(rel, "frontmatter（先頭の --- ブロック）がありません")
        return None, body
    try:
        return parse_yaml_subset(fm_src), body
    except ValueError as e:
        rep.error(rel, f"frontmatter を解析できません: {e}")
        return None, body


def collect_req_ids(project_dir):
    ids = set()
    for p in glob.glob(os.path.join(project_dir, "doc", "requirements", "*.md")):
        with open(p, encoding="utf-8") as fh:
            fm_src, _ = split_frontmatter(fh.read())
        if fm_src is None:
            continue
        try:
            fm = parse_yaml_subset(fm_src)
        except ValueError:
            continue
        for r in fm.get("requirements") or []:
            if isinstance(r, dict) and r.get("id"):
                ids.add(str(r["id"]))
    return ids


def check_ids(rep, rel, items, pattern, body):
    seen = set()
    for it in items:
        if not isinstance(it, dict) or not it.get("id"):
            rep.error(rel, f"id の無い項目があります: {it!r}")
            continue
        i = str(it["id"])
        if not re.match(pattern, i):
            rep.error(rel, f"{i}: ID の形式が不正です（期待: {pattern}）")
        if i in seen:
            rep.error(rel, f"{i}: ID が重複しています")
        seen.add(i)
        if i not in body:
            rep.error(rel, f"{i}: frontmatter にあるが本文に見出しがありません")
        st = it.get("status")
        if st is not None and st not in STATUS_VALUES:
            rep.error(rel, f"{i}: status は added|modified のみ（{st}）")
    return seen


def check_covers(rep, rel, items, req_ids):
    for it in items:
        if not isinstance(it, dict):
            continue
        covers = it.get("covers")
        if covers is None:
            continue
        if not isinstance(covers, list):
            rep.error(rel, f"{it.get('id')}: covers はリストにしてください")
            continue
        for c in covers:
            if not re.match(r"^REQ-\d{3,}$", str(c)):
                rep.error(rel, f"{it.get('id')}: covers の値が REQ-NNN ではありません（{c}）")
            elif req_ids and str(c) not in req_ids:
                rep.error(rel, f"{it.get('id')}: covers の {c} が doc/requirements/ に存在しません")


def check_implemented_by(rep, rel, items, project_dir):
    for it in items:
        if not isinstance(it, dict) or not it.get("implemented_by"):
            continue
        ref = str(it["implemented_by"])
        if "::" not in ref:
            rep.error(rel, f"{it.get('id')}: implemented_by は path::関数名 の形式にしてください（{ref}）")
            continue
        path, func = ref.split("::", 1)
        abs_path = os.path.join(project_dir, path)
        if not os.path.isfile(abs_path):
            rep.error(rel, f"{it.get('id')}: implemented_by のファイルがありません: {path}")
            continue
        with open(abs_path, encoding="utf-8", errors="replace") as fh:
            if func not in fh.read():
                rep.error(rel, f"{it.get('id')}: implemented_by の {func} が {path} に見つかりません")


def validate_doc(path, project_dir, rep):
    rel = os.path.relpath(path, project_dir)
    dtype = doc_type_of(rel)
    if dtype not in ID_PATTERNS:
        return
    fm, body = load_frontmatter(path, rep, rel)
    if fm is None:
        return
    declared = fm.get("doc_type")
    if declared and declared != dtype:
        rep.error(rel, f"doc_type が {declared} ですがディレクトリは {dtype} です")
    list_key, pattern = ID_PATTERNS[dtype]
    items = fm.get(list_key)
    if items is None:
        if dtype == "infra-spec":
            rep.warn(rel, f"frontmatter に {list_key} がありません")
            return
        rep.error(rel, f"frontmatter に {list_key} がありません")
        return
    if not isinstance(items, list):
        rep.error(rel, f"{list_key} はリストにしてください")
        return
    ids = check_ids(rep, rel, items, pattern, body)
    if dtype != "requirements":
        req_ids = collect_req_ids(project_dir)
        if not req_ids:
            rep.warn(rel, "doc/requirements/ に REQ が無いため covers の存在確認をスキップしました")
        check_covers(rep, rel, items, req_ids)
    if dtype == "test-spec":
        check_implemented_by(rep, rel, items, project_dir)
        top = fm.get("covers")
        if isinstance(top, list):
            union = {str(c) for it in items if isinstance(it, dict) for c in (it.get("covers") or [])}
            missing = union - {str(c) for c in top}
            if missing:
                rep.warn(rel, f"test_cases の covers にあるが先頭の covers に無い REQ: {sorted(missing)}")
    if dtype == "api-spec":
        for it in items:
            if isinstance(it, dict) and (not it.get("method") or not it.get("path")):
                rep.error(rel, f"{it.get('id')}: method と path は必須です")
    return ids


def validate_checklist(path, project_dir, rep):
    rel = os.path.relpath(path, project_dir)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r"^## ステージ進捗\s*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        rep.error(rel, "「## ステージ進捗」セクションがありません")
        return
    section = m.group(1)
    for n, stage in enumerate(STAGES, 1):
        if not re.search(rf"^- \[[ x]\] {n}\. {stage}:", section, re.M):
            rep.error(rel, f"ステージ進捗に「- [ ] {n}. {stage}:」の行がありません")
    if re.search(r"^## フェーズ進捗", text, re.M):
        rep.error(rel, "旧形式の「## フェーズ進捗」が残っています")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-dir", default=os.getcwd())
    ap.add_argument("--all", action="store_true")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    project_dir = os.path.abspath(args.project_dir)

    files = list(args.files)
    if args.all:
        for d in ID_PATTERNS:
            files += sorted(glob.glob(os.path.join(project_dir, "doc", d, "*.md")))
        cl = os.path.join(project_dir, "doc", "process", "task_checklist.md")
        if os.path.exists(cl):
            files.append(cl)
    if not files:
        ap.print_usage()
        return 2

    rep = Report()
    for f in files:
        p = f if os.path.isabs(f) else os.path.join(project_dir, f)
        if not os.path.exists(p):
            rep.error(os.path.relpath(p, project_dir), "ファイルがありません")
            continue
        if os.path.basename(p) == "task_checklist.md":
            validate_checklist(p, project_dir, rep)
        else:
            validate_doc(p, project_dir, rep)

    for line in rep.errors + rep.warnings:
        print(line)
    print(f"summary: {len(rep.errors)} errors, {len(rep.warnings)} warnings")
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
