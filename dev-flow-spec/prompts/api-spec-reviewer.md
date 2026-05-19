# api-spec-reviewer プロンプト

`api-spec-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 全エンドポイントのリクエスト・レスポンス定義が揃っているか
- 認証・認可の記載があるか
- エラーケースが網羅されているか

問題があれば `api-spec-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「api-spec レビュー完了: {API_SPEC_PATH}」と SendMessage で報告してください。
