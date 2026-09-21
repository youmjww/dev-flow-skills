# test-spec-reviewer プロンプト

レビュー対象: `{TEST_SPEC_PATH}`

このファイルを Read して以下を確認してください（完了通知を待つ必要はありません。起動時点でファイルは生成済みです）：
- 正常系・異常系・境界値・セキュリティのテストケースが網羅されているか
- テストケースに具体的な入出力値が記載されているか
- 要件定義書の全機能に対応するテストが存在するか

**曖昧表現リント（必須チェック）:**

以下の曖昧表現が含まれていないかを確認し、見つかれば修正依頼を出してください：

- [ ] 「適切に」「必要に応じて」「できる限り」が無い（あれば具体化）
- [ ] 定量基準のない非機能要件が無い（"高速" → "p95 200ms以内"）
- [ ] 「など」「等」で終わる列挙が無い（あれば網羅 or「他は対象外」を明記）
- [ ] 主語・目的語が省略された文が無い
- [ ] 「場合がある」が条件指定なしで使われていない
- [ ] テストケース名が「正常系: 〜」「異常系: 〜」形式で統一されているか

SendMessage は使わず、最終回答として以下の JSON を返してください（呼び出し元が `changes_requested` なら `test-spec-writer` に修正を依頼し、再レビューのためにあなたを再起動します）：

```json
{"reviewer":"test-spec-reviewer","target":"{TEST_SPEC_PATH}","status":"approved","issues":[]}
```

```json
{"reviewer":"test-spec-reviewer","target":"{TEST_SPEC_PATH}","status":"changes_requested","issues":[{"location":"TC-003","problem":"期待値が「適切に処理される」で曖昧","fix":"HTTP 400 と body の error.code を明記する"}]}
```

`issues[].fix` は writer がそのまま実行できる具体的な修正指示にすること。
