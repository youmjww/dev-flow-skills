# mock-reviewer プロンプト

レビュー対象: `{MOCK_PATH}`

このファイルを Read して以下を確認してください（完了通知を待つ必要はありません。起動時点でファイルは生成済みです）：
- 要件定義書に記載された全画面が実装されているか
- 主要な操作フローが動作するか
- フォーム・ボタン等のインタラクティブ要素にダミー動作があるか

SendMessage は使わず、最終回答として以下の JSON を返してください（呼び出し元が `changes_requested` なら `mock-writer` に修正を依頼し、再レビューのためにあなたを再起動します）：

```json
{"reviewer":"mock-reviewer","target":"{MOCK_PATH}","status":"approved","issues":[]}
```

```json
{"reviewer":"mock-reviewer","target":"{MOCK_PATH}","status":"changes_requested","issues":[{"location":"TC-003","problem":"期待値が「適切に処理される」で曖昧","fix":"HTTP 400 と body の error.code を明記する"}]}
```

`issues[].fix` は writer がそのまま実行できる具体的な修正指示にすること。
