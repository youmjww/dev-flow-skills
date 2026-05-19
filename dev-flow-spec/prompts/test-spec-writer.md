# テスト定義書生成プロンプト

要件定義書を Read ツールで読み込み、テスト定義書を生成して TEST_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{TEST_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/test-spec/{同名}.md` とする）

**テスト定義書フォーマット:**

```markdown
# テスト定義書

## 正常系テストケース
## 異常系テストケース
## 境界値テスト
## セキュリティテスト
## パフォーマンステスト（必要な場合）
```

完了したら `test-spec-reviewer` に「テスト定義書の生成が完了しました。対象ファイル: {TEST_SPEC_PATH}」と SendMessage で報告してください。
