# as-is テスト定義書生成プロンプト

既存テストをテスト定義書の TC-NNN に対応付けて `{TEST_SPEC_PATH}` に書き出してください。**既存テストに無いテストケースは作らない**（as-is に無いものを捏造しない）。

入力:
- 棚卸し: `{INVENTORY_PATH}`（「既存テスト」表が起点）
- 要件定義書: {REQUIREMENTS_PATHS}
技術スタック: `{tech_stack}`

## 手順

1. inventory の既存テスト 1 行につき、テスト関数を Read して Given / When / Then を抽出する
2. そのテストが検証している振る舞いに対応する REQ-ID を要件定義書から探して `covers` に入れる。対応する REQ が無ければ `covers: []` とし、最終回答で報告する（要件定義書側の漏れの可能性）
3. パラメタライズドテスト・テーブル駆動テストは、ケースごとに TC を分けず 1 TC にまとめ、ケース一覧を本文に書く
4. 具体的な入出力値はテストコードの値をそのまま書く

## 出力フォーマット

```markdown
---
doc_type: test-spec
origin: bootstrap
covers: [REQ-001, ...]
test_cases:
  - id: TC-001
    title: （テスト関数名を人が読める形にしたもの）
    covers: [REQ-001]
    implemented_by: path/to/x_test.go::TestLogin_Success   # compliance の機械的検証がこれを使う
    kind: unit | integration | e2e
---

# as-is テスト定義書

## 正常系テストケース

### TC-001: （タイトル）
**対象要件**: REQ-001
**実装**: `path/to/x_test.go::TestLogin_Success`

```gherkin
Feature: ...
  Scenario: ...
    Given ...
    When ...
    Then ...
```

**具体的な入出力値:**
- 入力: （テストコードの値）
- 期待出力: （アサーションの値）

## 異常系テストケース
## 境界値テスト
## セキュリティテスト
```

完了したら SendMessage は使わず、最終回答として「TC 件数 / 既存テスト件数」「`covers: []` になった TC 一覧」「テストが無い REQ の一覧（要件定義書の REQ のうち covers に一度も現れないもの）」を返してください。
