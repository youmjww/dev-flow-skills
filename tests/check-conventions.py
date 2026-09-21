#!/usr/bin/env python3
"""reference/conventions/*.md の構造チェック（静的）。
各ファイルに「書き方」「レビューチェックリスト」「標準コマンド」があり、
チェックリスト行がルール ID（prefix/name）・重大度（blocker|major|minor）を持つことを確認する。"""
import glob, os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dev-flow-implementation", "reference", "conventions")
errors = []
for f in sorted(glob.glob(os.path.join(root, "*.md"))):
    name = os.path.basename(f)
    if name in ("README.md", "_template.md"):
        continue
    s = open(f, encoding="utf-8").read()
    for sec in ("## 書き方", "## レビューチェックリスト", "## 標準コマンド"):
        if sec not in s:
            errors.append(f"{name}: セクション「{sec}」がありません")
    rows = re.findall(r"^\| `([a-z]+)/([a-z0-9-]+)` \| (\w+) \|", s, re.M)
    if not rows:
        errors.append(f"{name}: チェックリストの行（| `prefix/rule` | severity |）が見つかりません")
    prefixes = {r[0] for r in rows}
    if len(prefixes) > 1:
        errors.append(f"{name}: ルール ID の prefix が混在しています: {sorted(prefixes)}")
    for pfx, rule, sev in rows:
        if sev not in ("blocker", "major", "minor"):
            errors.append(f"{name}: {pfx}/{rule} の重大度 '{sev}' が不正です")
    ids = [f"{p}/{r}" for p, r, _ in rows]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        errors.append(f"{name}: ルール ID が重複: {sorted(dup)}")
    sevs = {r[2] for r in rows}
    if not {"blocker", "major"} <= sevs:
        errors.append(f"{name}: blocker と major の両方が必要です（{sorted(sevs)}）")
for e in errors:
    print("ERROR", e)
print(f"conventions: {len(errors)} errors")
sys.exit(1 if errors else 0)
