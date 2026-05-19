# mock-reviewer プロンプト

`mock-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 要件定義書に記載された全画面が実装されているか
- 主要な操作フローが動作するか
- フォーム・ボタン等のインタラクティブ要素にダミー動作があるか

問題があれば `mock-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「mock レビュー完了: {MOCK_PATH}」と SendMessage で報告してください。
