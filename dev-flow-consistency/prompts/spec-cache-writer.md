# スペックキャッシュ生成プロンプト

開発モード: `{MODE}`
baseline_commit: `{BASELINE_COMMIT}`

以下のドキュメントを Read ツールで読み込み、実装に必要な情報のみを抽出した軽量参照ファイル `doc/internal/spec_cache.md` を生成してください。

- 要件定義書（全ファイルを順に読み込んでください）: {REQUIREMENTS_PATHS}
- API仕様書（IS_API=true の場合）: `{API_SPEC_PATH}`
- インフラ仕様書（IS_INFRA=true の場合）: `{INFRA_SPEC_PATH}`

**mode = "incremental" の場合：**

`doc/internal/spec_cache.md` が既に存在する場合は上書きせず、追加された要件に関する差分情報のみを末尾に追記してください：

```markdown
---
## 追加要件（{今日の日付}）

（追加された要件に関する型定義・エンドポイント・ルール等のみ）
```

**抽出する情報:**
- 型定義・データモデル（構造体・スキーマ・型）
- インターフェース・関数シグネチャ
- エンドポイント一覧（メソッド・パス・リクエスト/レスポンス概要）
- リソース一覧（種別・名前・設定項目）
- 認証・認可ルール
- 重要なビジネスルール・制約

**除外する情報:** 背景説明、経緯、UI描写、冗長な文章。

`doc/internal/spec_cache.md` に書き出してください。
完了したら `consistency-orchestrator` に「spec-cache 生成完了: doc/internal/spec_cache.md」と SendMessage で報告してください。
