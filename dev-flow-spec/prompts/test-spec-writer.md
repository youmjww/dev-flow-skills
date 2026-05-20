# テスト定義書生成プロンプト

要件定義書を Read ツールで読み込み、テスト定義書を生成して TEST_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{TEST_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/test-spec/{同名}.md` とする）

**テスト定義書フォーマット:**

各テストケースには **Gherkin 形式の Given-When-Then シナリオ**を含めること。これにより仕様が機械可読になり、BDD フレームワークとの連携が可能になります。

```markdown
# テスト定義書

## 正常系テストケース

### TC-001: （テストケース名）
**対象要件**: REQ-001
**API**: API-001

```gherkin
Feature: （機能名）
  Scenario: （シナリオ名）
    Given （前提条件）
    When （操作）
    Then （期待結果）
    And （追加の期待結果）
```

**具体的な入出力値:**
- 入力: `{"field": "value"}`
- 期待出力: `{"id": "123", "status": "ok"}`

## 異常系テストケース

### TC-00N: ...

（Gherkin フォーマット必須、入出力値必須）

## 境界値テスト

## セキュリティテスト

## パフォーマンステスト（必要な場合）
```

完了したら `test-spec-reviewer` に「テスト定義書の生成が完了しました。対象ファイル: {TEST_SPEC_PATH}」と SendMessage で報告してください。
