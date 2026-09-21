# API仕様書生成プロンプト

要件定義書を Read ツールで読み込み、API仕様書を生成して API_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{API_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/api-spec/{同名}.md` とする）
技術スタック: `{tech_stack}`

**生成モード: `{KIND}`**（`feature` = 新規生成 / `change` = 差分更新 / `fix` = 不具合修正）

`{KIND}` が `change` または `fix` で出力先ファイルが既に存在する場合は**差分更新モード**で動作すること：

- 既存ファイルを最初に Read し、**既存の ID（API-NNN）と項目は一切振り直さない・削除しない**
- 変更対象: `{CHANGED_REQ_IDS}`（requirements の差分。`added` / `modified` / `removed` 付き）
  - `added` の REQ → 新しい ID を**既存の最大番号 + 1** から採番して追記
  - `modified` の REQ → その REQ を `covers` に持つ既存項目だけを書き換え、他はそのまま
  - `removed` の REQ → 該当項目を削除せず、見出しに `（廃止: REQ-NNN 削除）` を付けて残す（履歴の追跡用。次回 compliance で除外対象になる）
- 追加・変更した項目には frontmatter に `status: added` / `status: modified` を付け、変更していない項目には付けない（reviewer と consistency の Impact Analysis がこれを見る）
- 最終回答に「追加した ID / 変更した ID / 触っていない ID 数」を必ず書く

`{KIND}` が `feature`、または出力先ファイルが存在しない場合は、従来どおり全文を新規生成する。

**API仕様書フォーマット:**

マークダウンの説明文に加えて、**OpenAPI 3.1.0 形式の YAML を fenced code block として埋め込む**こと。トレーサビリティIDとの連携のために `x-req-id` と `x-api-id` の vendor extension を使用すること。

```markdown
# API仕様書

## 概要

## エンドポイント一覧

| メソッド | パス | 概要 |
|---|---|---|

## OpenAPI仕様

```yaml
openapi: 3.1.0
info:
  title: {API名}
  version: "1.0.0"
paths:
  /example:
    post:
      x-req-id: REQ-001
      x-api-id: API-001
      summary: （エンドポイント概要）
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ExampleRequest'
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ExampleResponse'
        '400':
          description: バリデーションエラー
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
components:
  schemas:
    ExampleRequest:
      type: object
      required: [field1]
      properties:
        field1:
          type: string
    ExampleResponse:
      type: object
      properties:
        id:
          type: string
    ErrorResponse:
      type: object
      properties:
        code:
          type: string
        message:
          type: string
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
```

## 認証・認可

## エラーコード一覧
```

完了したら SendMessage は使わず、最終回答として次を返してください（呼び出し元がこの回答を受け取ってレビュアーを起動します）：

```
API仕様書の生成が完了しました。対象ファイル: {API_SPEC_PATH}
（生成した ID 一覧・判断に迷った点・要件定義書に不足していた情報を箇条書き）
```

修正依頼を受け取って再実行する場合も、修正内容の要約を同じ形式で返してください。

Write 直後に「dev-flow hook: ... がスキーマ違反です」というフィードバックが返った場合は、列挙された ERROR をすべて直して**同じファイルを書き直す**こと（frontmatter の ID 形式・重複、`covers` の REQ が要件定義書に存在するか、本文に `### ID:` 見出しがあるか）。
