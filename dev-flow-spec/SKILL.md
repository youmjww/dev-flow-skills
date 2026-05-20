---
name: dev-flow-spec
description: AI駆動開発フローのドキュメント生成フェーズ（Phase 3-4）。テスト定義書（Gherkin）・API仕様書（OpenAPI 3.1.0）・インフラ仕様書・UIモックを `doc-team` で並列生成し、frontmatter に `covers: [REQ-NNN]` を付与してエージェントレビューと人間レビューを得ます。要件定義承認後の `/dev-flow` 継続時、または `--from=spec` で起動時に使用します。
model: haiku
allowed-tools: Read Write Edit Bash TeamCreate SendMessage AskUserQuestion
paths: doc/process/state.json
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

最初に以下のエージェントを起動（`team_name="doc-team"`, `name="doc-orchestrator"`, `run_in_background=true`, `model="haiku"`）。

プロンプトは `prompts/doc-orchestrator.md` を Read ツールで読み込み、プレースホルダー（`{IS_API}`, `{IS_INFRA}`, `{IS_GUI}`）を実際の値に置換してから Agent に渡してください。

### 3b. テスト定義書の生成

以下のエージェントを起動（`team_name="doc-team"`, `name="test-spec-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）。

プロンプトは `prompts/test-spec-writer.md` を Read ツールで読み込み、プレースホルダー（`{REQUIREMENTS_PATHS}`, `{TEST_SPEC_PATH}`）を実際の値に置換してから Agent に渡してください。

**テスト定義書の frontmatter テンプレート（writer に指示すること）:**

```markdown
---
doc_type: test-spec
covers:
  - REQ-001
  - REQ-002
test_cases:
  - id: TC-001
    title: （テストケースタイトル）
    covers: [REQ-001]
  - id: TC-002
    title: （テストケースタイトル）
    covers: [REQ-001, REQ-002]
---
```

要件定義書の `requirements[].id`（REQ-NNN）を参照して `covers` フィールドを埋めること。

### 3c. API仕様書の生成（IS_API=true の場合）

3b と同時に以下のエージェントを起動（`team_name="doc-team"`, `name="api-spec-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）。

プロンプトは `prompts/api-spec-writer.md` を Read ツールで読み込み、プレースホルダー（`{REQUIREMENTS_PATHS}`, `{API_SPEC_PATH}`, `{tech_stack}`）を実際の値に置換してから Agent に渡してください。

**API仕様書の frontmatter テンプレート（writer に指示すること）:**

```markdown
---
doc_type: api-spec
endpoints:
  - id: API-001
    method: POST
    path: /example
    covers: [REQ-001]
  - id: API-002
    method: GET
    path: /example/{id}
    covers: [REQ-002]
---
```

要件定義書の `requirements[].id` を参照して `covers` フィールドを埋めること。

### 3d. インフラ仕様書の生成（IS_INFRA=true の場合）

3b・3c と同時に以下のエージェントを起動（`team_name="doc-team"`, `name="infra-spec-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）。

プロンプトは `prompts/infra-spec-writer.md` を Read ツールで読み込み、プレースホルダー（`{REQUIREMENTS_PATHS}`, `{INFRA_SPEC_PATH}`, `{tech_stack}`）を実際の値に置換してから Agent に渡してください。

### 3e. モック HTML の生成（IS_GUI=true の場合）

3b・3c・3d と同時に以下のエージェントを起動（`team_name="doc-team"`, `name="mock-writer"`, `run_in_background=true`, `model="sonnet"`, `mode="acceptEdits"`）。

プロンプトは `prompts/mock-writer.md` を Read ツールで読み込み、プレースホルダー（`{REQUIREMENTS_PATHS}`, `{MOCK_PATH}`, `{tech_stack}`）を実際の値に置換してから Agent に渡してください。

### 3f. レビュアーの起動

3b・3c・3d・3e と同時に、以下のレビュアーエージェントを起動します。各レビュアーは writer からの SendMessage を待機します。

各レビュアーのプロンプトは以下のファイルを Read ツールで読み込み、プレースホルダーを実際の値に置換してから Agent に渡してください：

| エージェント | プロンプトファイル | 起動条件 |
|---|---|---|
| test-spec-reviewer | `prompts/test-spec-reviewer.md` | 常に起動 |
| api-spec-reviewer | `prompts/api-spec-reviewer.md` | IS_API=true の場合 |
| infra-spec-reviewer | `prompts/infra-spec-reviewer.md` | IS_INFRA=true の場合 |
| mock-reviewer | `prompts/mock-reviewer.md` | IS_GUI=true の場合 |

すべてのレビュアーは `team_name="doc-team"`, `run_in_background=true`, `model="sonnet"` で起動します。

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
