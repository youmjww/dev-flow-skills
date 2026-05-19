---
skill: dev-flow:phase-spec
description: ドキュメント生成フェーズ（Phase 3-4）- テスト定義書・API仕様書・モックを並列生成してレビュー
model: haiku
---

# Phase 3-4: ドキュメント生成とレビュー

## 入力

状態ファイル `doc/process/state.json` から読み込み：
- requirements_paths
- test_spec_path（未指定の場合は自動決定）
- api_spec_path（未指定の場合は自動決定）
- mock_path（未指定の場合は自動決定）
- tech_stack
- is_gui
- is_api
- is_e2e

## Phase 3: ドキュメント生成

### 3a. テスト定義書の生成（バックグラウンド）

以下のプロンプトで Agent を起動（`run_in_background=true`, `model="sonnet"`）：

---
**テスト定義書生成プロンプト**

要件定義書を Read ツールで読み込み、テスト定義書を生成して TEST_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{TEST_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/test-spec/{同名}.md` とする）

**テスト定義書フォーマット:**

```markdown
# テスト定義書

## 正常系テストケース
## 異常系テストケース
## 境界値テスト
## セキュリティテスト
## パフォーマンステスト（必要な場合）
```

完了したら報告してください。

---

### 3b. API仕様書の生成（IS_API=true の場合・バックグラウンド）

3a と同時に以下のプロンプトで Agent を起動（`run_in_background=true`, `model="sonnet"`）：

---
**API仕様書生成プロンプト**

要件定義書を Read ツールで読み込み、API仕様書を生成して API_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{API_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/api-spec/{同名}.md` とする）
技術スタック: `{tech_stack}`

**API仕様書フォーマット:**

```markdown
# API仕様書

## 概要

## エンドポイント一覧

| メソッド | パス | 概要 |
|---|---|---|

## エンドポイント詳細

### {METHOD} {path}

**概要**: ...

**リクエスト**
- ヘッダー:
- パスパラメータ:
- クエリパラメータ:
- ボディ（JSON スキーマ）:

**レスポンス**
- 成功時（ステータスコード・ボディ）:
- エラー時（ステータスコード・ボディ）:

## 認証・認可

## エラーコード一覧
```

完了したら報告してください。

---

### 3c. モック HTML の生成（IS_GUI=true の場合・バックグラウンド）

3a・3b と同時に以下のプロンプトで Agent を起動（`run_in_background=true`, `model="sonnet"`）：

---
**モック生成プロンプト**

要件定義書を Read ツールで読み込み、UI モックを HTML ファイルとして生成して MOCK_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{MOCK_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/mock/{同名}.html`）
技術スタック: `{tech_stack}`

**モック生成ガイドライン:**
- 1ファイルの自己完結した HTML（外部 CDN は可）
- 画面遷移がある場合は JavaScript でページ切り替えを実装する
- 要件定義書に記載された全画面・全操作フローを網羅する
- スタイルは簡素で構わないが、レイアウト・要素の配置は要件を忠実に反映する
- フォーム・ボタン等のインタラクティブ要素はダミーデータで動作させる
- 実装の根拠として使用するため、コンポーネント・要素には分かりやすい id / class を付与する

完了したら報告してください。

---

### 3d. バックグラウンドエージェントの完了待機

起動した全エージェント（テスト定義書・API仕様書・モック）の完了通知を待ちます。

---

## Phase 4: レビュー

AskUserQuestion ツールで以下を同時に提示してレビューを依頼：

- テスト定義書（TEST_SPEC_PATH）
- API仕様書（API_SPEC_PATH）（IS_API=true の場合）
- モック HTML（MOCK_PATH）（IS_GUI=true の場合）— ブラウザで開いて確認するよう案内する

| 対象 | 結果 | 動作 |
|---|---|---|
| テスト定義書 | 修正が必要 | 指摘内容を受けて Phase 3a に戻る |
| API仕様書 | 修正が必要 | 指摘内容を受けて Phase 3b に戻る |
| モック | 修正が必要 | 指摘内容を受けて Phase 3c に戻る |
| すべて承認 | — | 出力処理へ進む |

---

## 出力

すべて承認されたら、以下を実行：

1. `doc/process/state.json` を更新：
   ```json
   {
     "current_phase": "phase_4",
     "test_spec_path": "確定したパス",
     "api_spec_path": "確定したパス",
     "mock_path": "確定したパス",
     ...
   }
   ```
2. 人間に「Phase 4 完了。次は `/dev-flow` を実行して Phase 4.5 に進んでください」と通知
