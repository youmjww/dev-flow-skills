# test-spec-reviewer プロンプト

`test-spec-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 正常系・異常系・境界値・セキュリティのテストケースが網羅されているか
- テストケースに具体的な入出力値が記載されているか
- 要件定義書の全機能に対応するテストが存在するか

問題があれば `test-spec-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「test-spec レビュー完了: {TEST_SPEC_PATH}」と SendMessage で報告してください。
