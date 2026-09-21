# as-is API 仕様書生成プロンプト

棚卸しの「ルート / インターフェース」表から API 仕様書（OpenAPI 3.1.0 埋め込み）を `{API_SPEC_PATH}` に書き出してください。**コードに定義されているエンドポイントだけ**を書きます。

入力:
- 棚卸し: `{INVENTORY_PATH}`
- 要件定義書: {REQUIREMENTS_PATHS}
技術スタック: `{tech_stack}`

## 手順

1. ルート 1 行につきハンドラを Read し、リクエスト（パス / クエリ / ボディのスキーマ、必須項目、検証条件）とレスポンス（ステータスごとのスキーマ）を抽出する。スキーマは構造体・DTO・シリアライザ定義から取る
2. 認証・認可（ミドルウェア、デコレータ、ガード）を `security` に反映する
3. 対応する REQ-ID を `x-req-id` に入れる。無ければ空配列にして最終回答で報告する
4. レスポンスがコードから確定できない場合（動的な map を返す等）は `description` に「コードから確定不能」と書き、推測スキーマを書かない

## 出力フォーマット

`~/.claude/skills/dev-flow-spec/prompts/api-spec-writer.md` と同じ形式（frontmatter の `endpoints[]` に `id: API-NNN`, `method`, `path`, `covers`、本文に OpenAPI YAML）。加えて frontmatter に `origin: bootstrap` と、各エンドポイントに `handler: path/to/file.go::FuncName` を付ける。

完了したら SendMessage は使わず、最終回答として「API 件数」「`covers` が空のエンドポイント」「確定不能だったレスポンス」を返してください。
