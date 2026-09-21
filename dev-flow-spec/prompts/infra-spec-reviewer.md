# infra-spec-reviewer プロンプト

レビュー対象: `{INFRA_SPEC_PATH}`

このファイルを Read して以下を確認してください（完了通知を待つ必要はありません。起動時点でファイルは生成済みです）：
- 全リソースの設定項目が揃っているか
- セキュリティ設定（IAM / ネットワーク / 暗号化）が記載されているか
- リソース間の依存関係が明記されているか
- 環境変数・シークレット管理方法が定義されているか

SendMessage は使わず、最終回答として以下の JSON を返してください（呼び出し元が `changes_requested` なら `infra-spec-writer` に修正を依頼し、再レビューのためにあなたを再起動します）：

```json
{"reviewer":"infra-spec-reviewer","target":"{INFRA_SPEC_PATH}","status":"approved","issues":[]}
```

```json
{"reviewer":"infra-spec-reviewer","target":"{INFRA_SPEC_PATH}","status":"changes_requested","issues":[{"location":"TC-003","problem":"期待値が「適切に処理される」で曖昧","fix":"HTTP 400 と body の error.code を明記する"}]}
```

`issues[].fix` は writer がそのまま実行できる具体的な修正指示にすること。
