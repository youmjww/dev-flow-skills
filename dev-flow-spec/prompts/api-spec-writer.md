# API仕様書生成プロンプト

要件定義書を Read ツールで読み込み、API仕様書を生成して API_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{API_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/api-spec/{同名}.md` とする）
技術スタック: `{tech_stack}`

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

完了したら `api-spec-reviewer` に「API仕様書の生成が完了しました。対象ファイル: {API_SPEC_PATH}」と SendMessage で報告してください。
