---
skill: dev-flow-spec
description: ドキュメント生成フェーズ（Phase 3-4）- テスト定義書・API仕様書・モックを並列生成してレビュー
---


# Phase 3-4: ドキュメント生成とレビュー

## 入力

状態ファイル `doc/process/state.json` から読み込み：
- requirements_paths
- test_spec_path（未指定の場合は自動決定）
- api_spec_path（未指定の場合は自動決定）
- infra_spec_path（未指定の場合は自動決定）
- mock_path（未指定の場合は自動決定）
- tech_stack
- is_gui
- is_api
- is_infra
- is_e2e

## Phase 3: ドキュメント生成

### 3-0. チーム作成

```
TeamCreate(name: "doc-team")
```

### 3a. オーケストレーターの起動

最初に以下のエージェントを起動（`team_name="doc-team"`, `name="doc-orchestrator"`, `run_in_background=true`, `model="haiku"`）：

---
**doc-orchestrator プロンプト**

あなたは doc-team のオーケストレーターです。
以下のエージェントからの完了通知を待ち、すべて揃ったら完了をメインに報告します：

- `test-spec-reviewer` からの「test-spec レビュー完了」通知を待つ
- `api-spec-reviewer` からの「api-spec レビュー完了」通知を待つ（IS_API=true の場合のみ）
- `infra-spec-reviewer` からの「infra-spec レビュー完了」通知を待つ（IS_INFRA=true の場合のみ）
- `mock-reviewer` からの「mock レビュー完了」通知を待つ（IS_GUI=true の場合のみ）

IS_API: `{IS_API}`
IS_INFRA: `{IS_INFRA}`
IS_GUI: `{IS_GUI}`

すべての通知が揃ったら、`SendMessage(to: "phase-spec-agent", message: "doc-team 全レビュー完了")` でこのスキルを実行している主体（phase-spec-agent）に報告してください。

---

### 3b. テスト定義書の生成

以下のプロンプトで Agent を起動（`team_name="doc-team"`, `name="test-spec-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）：

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

完了したら `test-spec-reviewer` に「テスト定義書の生成が完了しました。対象ファイル: {TEST_SPEC_PATH}」と SendMessage で報告してください。

---

### 3c. API仕様書の生成（IS_API=true の場合）

3b と同時に以下のプロンプトで Agent を起動（`team_name="doc-team"`, `name="api-spec-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）：

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

完了したら `api-spec-reviewer` に「API仕様書の生成が完了しました。対象ファイル: {API_SPEC_PATH}」と SendMessage で報告してください。

---

### 3d. インフラ仕様書の生成（IS_INFRA=true の場合）

3b・3c と同時に以下のプロンプトで Agent を起動（`team_name="doc-team"`, `name="infra-spec-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）：

---
**インフラ仕様書生成プロンプト**

要件定義書を Read ツールで読み込み、インフラ仕様書を生成して INFRA_SPEC_PATH に書き出してください。

要件定義書（全ファイルを順に Read ツールで読み込み、内容を統合してください）:
{REQUIREMENTS_PATHS}
出力先: `{INFRA_SPEC_PATH}`（未指定の場合は REQUIREMENTS_PATHS の先頭ファイル名を元に `doc/infra-spec/{同名}.md` とする）
技術スタック: `{tech_stack}`

**インフラ仕様書フォーマット:**

```markdown
# インフラ仕様書

## 概要

## リソース一覧

| リソース種別 | 名前 | 概要 |
|---|---|---|

## リソース詳細

### {リソース種別} {名前}

**概要**: ...

**設定項目**:
- パラメータ1: 値
- パラメータ2: 値

**依存リソース**:
- リソースA（理由）
- リソースB（理由）

**セキュリティ設定**:
- IAM ロール / ポリシー
- ネットワークアクセス制限
- 暗号化設定

## ネットワーク構成

## 環境変数・シークレット

## モニタリング・アラート設定
```

完了したら `infra-spec-reviewer` に「インフラ仕様書の生成が完了しました。対象ファイル: {INFRA_SPEC_PATH}」と SendMessage で報告してください。

---

### 3e. モック HTML の生成（IS_GUI=true の場合）

3b・3c と同時に以下のプロンプトで Agent を起動（`team_name="doc-team"`, `name="mock-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）：

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

完了したら `mock-reviewer` に「モックの生成が完了しました。対象ファイル: {MOCK_PATH}」と SendMessage で報告してください。

---

### 3f. レビュアーの起動

3b・3c・3d・3e と同時に、以下のレビュアーエージェントを起動します。各レビュアーは writer からの SendMessage を待機します。

**test-spec-reviewer**（`team_name="doc-team"`, `name="test-spec-reviewer"`, `run_in_background=true`, `model="sonnet"`）：

---
`test-spec-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 正常系・異常系・境界値・セキュリティのテストケースが網羅されているか
- テストケースに具体的な入出力値が記載されているか
- 要件定義書の全機能に対応するテストが存在するか

問題があれば `test-spec-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「test-spec レビュー完了: {TEST_SPEC_PATH}」と SendMessage で報告してください。

---

**api-spec-reviewer**（IS_API=true の場合、`team_name="doc-team"`, `name="api-spec-reviewer"`, `run_in_background=true`, `model="sonnet"`）：

---
`api-spec-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 全エンドポイントのリクエスト・レスポンス定義が揃っているか
- 認証・認可の記載があるか
- エラーケースが網羅されているか

問題があれば `api-spec-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「api-spec レビュー完了: {API_SPEC_PATH}」と SendMessage で報告してください。

---

**infra-spec-reviewer**（IS_INFRA=true の場合、`team_name="doc-team"`, `name="infra-spec-reviewer"`, `run_in_background=true`, `model="sonnet"`）：

---
`infra-spec-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 全リソースの設定項目が揃っているか
- セキュリティ設定（IAM / ネットワーク / 暗号化）が記載されているか
- リソース間の依存関係が明記されているか
- 環境変数・シークレット管理方法が定義されているか

問題があれば `infra-spec-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「infra-spec レビュー完了: {INFRA_SPEC_PATH}」と SendMessage で報告してください。

---

**mock-reviewer**（IS_GUI=true の場合、`team_name="doc-team"`, `name="mock-reviewer"`, `run_in_background=true`, `model="sonnet"`）：

---
`mock-writer` からの完了通知を待ち、通知が届いたらファイルを Read して以下を確認してください：
- 要件定義書に記載された全画面が実装されているか
- 主要な操作フローが動作するか
- フォーム・ボタン等のインタラクティブ要素にダミー動作があるか

問題があれば `mock-writer` に SendMessage で修正依頼を送り、再完了通知を待ってください。
問題なければ `doc-orchestrator` に「mock レビュー完了: {MOCK_PATH}」と SendMessage で報告してください。

---

### 3f. 完了待機

`doc-orchestrator` からの「doc-team 全レビュー完了」通知を待ちます。

通知が届かない場合（エージェントが途中でエラー終了した等）は、以下の手順でリカバリします：
1. 各ドキュメントファイル（TEST_SPEC_PATH / API_SPEC_PATH / INFRA_SPEC_PATH / MOCK_PATH）の存在を Bash で確認する
2. ファイルが存在すれば内容を Read して品質を直接確認し、問題なければ Phase 4 の人間レビューへ進む
3. ファイルが存在しなければ、該当する writer を Agent で再起動して生成し直す

---

## Phase 4: 人間レビュー

AskUserQuestion ツールで以下を同時に提示してレビューを依頼：

- テスト定義書（TEST_SPEC_PATH）
- API仕様書（API_SPEC_PATH）（IS_API=true の場合）
- インフラ仕様書（INFRA_SPEC_PATH）（IS_INFRA=true の場合）
- モック HTML（MOCK_PATH）（IS_GUI=true の場合）— ブラウザで開いて確認するよう案内する

| 対象 | 結果 | 動作 |
|---|---|---|
| テスト定義書 | 修正が必要 | 指摘内容を `test-spec-writer` に SendMessage して再生成、完了後 `test-spec-reviewer` が再レビュー |
| API仕様書 | 修正が必要 | 指摘内容を `api-spec-writer` に SendMessage して再生成、完了後 `api-spec-reviewer` が再レビュー |
| モック | 修正が必要 | 指摘内容を `mock-writer` に SendMessage して再生成、完了後 `mock-reviewer` が再レビュー |
| すべて承認 | — | 出力処理へ進む |

**SendMessage が届かない場合（writer が既に終了済み）:**
SendMessage の送信先エージェントが非アクティブな場合は、Agent ツールで同じ `name` と `team_name` を使って新規起動し、修正依頼プロンプトを直接渡してください。
例: `Agent(name="test-spec-writer", team_name="doc-team", run_in_background=true, model="sonnet", mode="acceptEdits", prompt="以下の指摘を反映してテスト定義書を修正してください: {指摘内容}。完了後 test-spec-reviewer に報告してください。")`

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
