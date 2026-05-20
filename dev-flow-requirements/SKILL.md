---
name: dev-flow-requirements
description: AI駆動開発フローの要件定義フェーズ（Phase 1-2）。ユーザーと対話しながら要件を深掘りして要件定義書を作成し、曖昧表現リント・用語集整備・REQ-NNN ID付与を行います。技術スタック・GUI/API/E2Eフラグを確定して `doc/process/state.json` を生成します。新規開発フローの初回起動時、または `--from=requirements` で要件から再開する時に使用します。
model: opus
allowed-tools: Read Write Edit Bash AskUserQuestion
---

# Phase 1-2: 要件定義

## 入力

状態ファイル `doc/process/state.json` から以下を読み込み（存在する場合）：
- requirements_paths
- tech_stack
- is_gui
- is_api
- is_e2e

## Phase 1: 要件定義

### 1a. 既存要件定義書の検索

Bash ツールで `doc/requirements/` 配下の `.md` ファイルを列挙します：

```bash
find doc/requirements -name "*.md" 2>/dev/null | sort
```

### 1b. モード選択

**ファイルが1件以上見つかった場合**

AskUserQuestion ツールで選択肢を提示します：
- 見つかったファイルを選択肢に列挙する（複数選択可）
- 「新規作成」を最後の選択肢として必ず加える

| 選択 | 動作 |
|---|---|
| 既存ファイルを1件以上選択 | 選択されたパスのリストを REQUIREMENTS_PATHS に設定し**修正モード**で進む |
| 新規作成 | ファイル名を人間に確認してから `doc/requirements/{名前}.md` を REQUIREMENTS_PATHS に設定し**新規作成モード**で進む |
| 既存ファイル＋新規作成 | 既存ファイルを REQUIREMENTS_PATHS に追加し、さらに新規ファイルを作成して追加する |

**ファイルが見つからなかった場合**

ファイル名を人間に確認してから `doc/requirements/{名前}.md` を REQUIREMENTS_PATHS に設定し**新規作成モード**で進む。

---

### 1c-A: 修正モード

選択された全ファイルを Read ツールで読み込み、内容を提示します。

対話の観点：
- 「どのファイルのどの部分を変更したいですか？」から始める
- 変更箇所のみ深掘りし、変更のない箇所は保持する
- 合意が取れたら該当ファイルに差分を反映して上書き保存する

修正完了後、変更内容から tech_stack / IS_GUI / IS_API / IS_E2E を再評価し、`doc/process/state.json` が存在する場合は該当フィールドを更新する。

---

### 1c-B: 新規作成モード

テキストで対話しながら要件を深掘りします。

以下の観点で質問・確認を行い、合意が取れたら REQUIREMENTS_PATHS の該当ファイル（新規の場合は新規ファイル）に書き出します：

- 機能要件（何をするか・しないか）
- 非機能要件（パフォーマンス・セキュリティ・スケーラビリティ）
- 技術スタック（language, framework, DB, test_framework, linter, formatter）
- 境界条件・エラーハンドリング
- 既存コードとの統合方法
- GUI の有無（IS_GUI）
- E2E テストの要否（IS_GUI=true の場合のみ確認。フレームワーク例: Playwright / Cypress）

**要件定義書フォーマット:**

```markdown
---
doc_type: requirements
doc_id: REQ-DOC-001
requirements:
  - id: REQ-001
    title: （要件タイトル）
    priority: must  # must / should / could
  - id: REQ-002
    title: （要件タイトル）
    priority: should
---

# 要件定義書

## 概要
## 技術スタック
## 機能要件

### REQ-001: （要件タイトル）
（本文）

### REQ-002: （要件タイトル）
（本文）

## 非機能要件
## API / インターフェース定義
## エラーハンドリング
## 除外範囲
## テスト戦略
- ユニットテスト: {test_framework}
- E2E テスト: {e2e_framework または "なし"}
```

**ID 採番規則:**

| 種別 | フォーマット | 例 |
|---|---|---|
| 要件 | `REQ-NNN`（3桁ゼロ埋め） | `REQ-001`, `REQ-042` |
| テストケース | `TC-NNN` | `TC-001`, `TC-023` |
| API エンドポイント | `API-NNN` | `API-001` |
| インフラリソース | `INFRA-NNN` | `INFRA-001` |
| 要件定義書ドキュメント | `REQ-DOC-NNN` | `REQ-DOC-001` |

複数の要件定義書が存在する場合は `doc_id` を `REQ-DOC-002` のように連番で付与し、`requirements` の ID は全ドキュメントを通じて一意にすること（同一 ID を複数ドキュメントに使わない）。

### tech_stack と GUI フラグの確定

要件定義書から以下の情報を抽出：

```
tech_stack = {
  language, framework, test_framework, db, linter, formatter, e2e_framework
}
```

以下のいずれかに該当する場合は **IS_GUI=true**：
- 要件定義書に「画面」「UI」「フロントエンド」「フロント」「GUI」「画面設計」が含まれる
- 技術スタックに React / Vue / Svelte / Next.js / Nuxt 等のフロントエンドフレームワークが含まれる
- 上記で判断できない場合は AskUserQuestion で人間に確認する

以下のいずれかに該当する場合は **IS_API=true**：
- 要件定義書に「API」「エンドポイント」「REST」「GraphQL」「gRPC」「HTTP」が含まれる
- 技術スタックに API フレームワーク（Gin / Echo / FastAPI / Express / NestJS 等）が含まれる
- 上記で判断できない場合は AskUserQuestion で人間に確認する

**IS_E2E の決定:**
- IS_GUI=false の場合は **IS_E2E=false**（E2E テストは GUI が前提）
- IS_GUI=true の場合は AskUserQuestion で「E2E テストを実施しますか？（Playwright / Cypress 等）」と人間に確認する
  - 「実施する」→ IS_E2E=true、使用フレームワークを tech_stack.e2e_framework に設定
  - 「実施しない」→ IS_E2E=false、e2e_framework=null

---

## Phase 2: 要件定義書レビュー

AskUserQuestion ツールを使用してブロッキングレビューを行います。

**レビュー前に曖昧表現リントを実施してください:**

以下の問題が残っている場合は人間レビュー前に自動修正または修正候補を提示します：

- 「適切に」「必要に応じて」「できる限り」→ 具体的な基準に置き換え
- 定量基準のない非機能要件 → 数値目標を追記（例: "高速" → "p95 500ms以内"）
- 「など」「等」で終わる列挙 → 網羅または「他は対象外」を明記
- 主語・目的語の省略 → 補完
- 「場合がある」を条件指定なしで使用 → 条件を明記
- `doc/requirements/_glossary.md` に未定義の専門用語 → 用語集に追加

**`doc/requirements/_glossary.md` の必須化:**

要件定義書で使われる専門用語・ドメイン固有語が定義されているか確認し、存在しない場合は作成してください。

```markdown
# 用語集

| 用語 | 定義 | 備考 |
|---|---|---|
| （用語名） | （正確な定義） | （関連する要件ID等） |
```

- 「承認する」→ 状態保存後に完了
- 「修正が必要」→ 指摘内容を受けて Phase 1 に戻る

---

## 出力

承認を受けたら、以下を実行：

1. `doc/process/` ディレクトリを作成：
   ```bash
   mkdir -p doc/process
   ```
2. 以下の内容で `doc/process/state.json` を作成：
   ```json
   {
     "current_phase": "phase_2",
     "mode": "{オーケストレーターから渡された mode（"full" または "incremental"）}",
     "baseline_commit": "{オーケストレーターから渡された baseline_commit（null または コミットハッシュ）}",
     "requirements_paths": [REQUIREMENTS_PATHS],
     "test_spec_path": null,
     "api_spec_path": null,
     "mock_path": null,
     "tech_stack": {
       "language": "...",
       "framework": "...",
       "test_framework": "...",
       "db": "...",
       "linter": "...",
       "formatter": "...",
       "e2e_framework": null
     },
     "is_gui": IS_GUI,
     "is_api": IS_API,
     "is_e2e": IS_E2E,
     "from": "requirements"
   }
   ```
3. 人間に「Phase 2 完了。次は `/dev-flow` を実行して Phase 3 に進んでください」と通知
