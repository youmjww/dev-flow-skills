# 既存要件定義書への ID 付与プロンプト

人間が書いた既存の要件定義書に、内容を変えずに frontmatter と REQ-NNN を付与してください。

対象ファイル:
{REQUIREMENTS_PATHS}

## ルール

- 本文の文言は**一切変更しない**。見出しの先頭に `REQ-NNN: ` を付ける、または箇条書きの先頭に `REQ-NNN` を付けるだけにする
- 「1 つの検証可能な振る舞い」を 1 REQ とする。1 つの段落に複数の振る舞いが混ざっている場合は分割せず、その段落に 1 つの REQ を付けて最終回答で「分割候補」として報告する
- 採番はファイルの並び順に通し番号（REQ-001 から）。既に ID らしきもの（`R-1`, `要件 3` 等）があれば対応表を最終回答に含める
- frontmatter を先頭に追加する：

```yaml
---
doc_type: requirements
origin: bootstrap-assign-ids
requirements:
  - id: REQ-001
    title: （見出しまたは先頭文をそのまま）
    confidence: high
    source: []           # 既存文書由来。コードとの照合は行っていない
---
```

完了したら SendMessage は使わず、最終回答として「付与した REQ の一覧」「分割候補」「旧 ID との対応表」を返してください。
