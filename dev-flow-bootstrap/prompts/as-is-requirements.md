# as-is 要件定義書生成プロンプト

`{INVENTORY_PATH}` を Read し、コードが**現に満たしている振る舞い**を要件定義書の形式で書き出してください。これは「あるべき仕様」ではなく観測記録です。

対象範囲: `{SCOPE}`
技術スタック: `{tech_stack}`

## 原則

- 1 つの REQ は「ユーザー / 呼び出し元から見える 1 つの振る舞い」。内部実装の詳細（関数名・クラス構成）は REQ にしない
- ルート・CLI・ジョブ・イベントハンドラを起点に、ハンドラの本体を Read して振る舞いを確定する。inventory の要約だけで書かない
- 入力の検証条件・エラー時の応答・権限チェック・副作用（DB 書き込み・外部呼び出し・通知）は**コードに書いてある限り**すべて REQ に含める
- 読み取れたが意図が不明な振る舞い（例: マジックナンバー、コメントの無い分岐）は書いたうえで `confidence: low` にする。省略しない
- コードに無い振る舞いを補完しない。「本来こうあるべき」は書かない

## 出力

機能領域ごとに `doc/requirements/as-is-{領域}.md`（例: `as-is-auth.md`, `as-is-orders.md`）。1 ファイル 30 REQ を目安に分割し、REQ-NNN はファイルをまたいで**通し番号**にする（REQ-001 から）。

```markdown
---
doc_type: requirements
origin: bootstrap
requirements:
  - id: REQ-001
    title: （振る舞いの短い名前）
    confidence: high        # high: テストまたは明示的なコードで確認 / medium: コードから読めるが未テスト / low: 推測を含む
    source:
      - path/to/handler.go:42
      - path/to/handler_test.go::TestLogin
---

# as-is 要件定義書: {領域}

## 概要
（この領域がやっていること 3〜5 行）

## 用語集
| 用語 | 定義（コード上の対応） |
|---|---|

## 要件

### REQ-001: （タイトル）
- **振る舞い**: （前提 → 入力 → 結果。具体値があれば書く）
- **エラー / 境界**: （検証条件と応答）
- **根拠**: `path:line`（複数可）
- **confidence**: high / medium / low（low の場合は何が推測かを 1 行）
```

完了したら SendMessage は使わず、最終回答として次を返してください：

```
as-is 要件定義書の生成が完了しました。
- ファイル: doc/requirements/as-is-xxx.md（REQ-001〜REQ-0NN）, ...
- confidence low の REQ: REQ-0XX（理由）, ...
- inventory にあったが REQ 化しなかったもの: （理由付き）
```
