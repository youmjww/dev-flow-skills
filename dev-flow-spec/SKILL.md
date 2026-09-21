---
name: dev-flow-spec
description: AI駆動開発フローのドキュメント生成フェーズ（Phase 3-4）。テスト定義書（Gherkin）・API仕様書（OpenAPI 3.1.0）・インフラ仕様書・UIモックを名前付きサブエージェントで並列生成し、frontmatter に `covers: [REQ-NNN]` を付与してエージェントレビューと人間レビューを得ます。要件定義承認後の `/dev-flow` 継続時、または `--from=spec` で起動時に使用します。
model: haiku
allowed-tools: Read Write Edit Bash Agent SendMessage AskUserQuestion
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

### 3-0. 実行モデル（チーム機能は使わない）

Agent Teams（`TeamCreate` / `team_name`）は使用しません。writer・reviewer はすべて **名前付きサブエージェント**として `Agent(name=..., run_in_background=true)` で起動し、完了通知（最終回答）を本エージェントが受け取って次の処理を決めます。

- writer / reviewer は SendMessage を送らず、**最終回答で結果を返す**（各 prompts/*.md に記載済み）
- 修正依頼は `SendMessage(to: "{writer name}", message: ...)` で **同じ名前の writer を再開**する（コンテキストを保ったまま続きから修正できる）
- 再開できない場合（エージェントが破棄されている等）は同じ `name` で `Agent` を新規起動し、修正依頼をプロンプトに含める
- 完了待ちは通知が届くまで待つ。`sleep` によるポーリングはしない

### 3a. writer の並列起動

以下のうち起動条件を満たすものを **同一ターンで同時に**起動します（`run_in_background=true`, `model="sonnet"`）。プロンプトは各ファイルを Read し、プレースホルダーを実際の値に置換してから Agent に渡してください。

| name | プロンプトファイル | プレースホルダー | 起動条件 |
|---|---|---|---|
| `test-spec-writer` | `prompts/test-spec-writer.md` | `{REQUIREMENTS_PATHS}`, `{TEST_SPEC_PATH}` | 常に |
| `api-spec-writer` | `prompts/api-spec-writer.md` | `{REQUIREMENTS_PATHS}`, `{API_SPEC_PATH}`, `{tech_stack}` | IS_API=true |
| `infra-spec-writer` | `prompts/infra-spec-writer.md` | `{REQUIREMENTS_PATHS}`, `{INFRA_SPEC_PATH}`, `{tech_stack}` | IS_INFRA=true |
| `mock-writer` | `prompts/mock-writer.md` | `{REQUIREMENTS_PATHS}`, `{MOCK_PATH}`, `{tech_stack}` | IS_GUI=true |

**テスト定義書の frontmatter テンプレート（test-spec-writer に指示すること）:**

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

**API仕様書の frontmatter テンプレート（api-spec-writer に指示すること）:**

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

いずれも要件定義書の `requirements[].id`（REQ-NNN）を参照して `covers` フィールドを埋めること。

### 3b. reviewer の起動（writer 完了ごと）

writer の完了通知を受け取るたびに、対応する reviewer を起動します（`run_in_background=true`, `model="sonnet"`）。他の writer の完了は待ちません。

| writer | reviewer name | プロンプトファイル | プレースホルダー |
|---|---|---|---|
| `test-spec-writer` | `test-spec-reviewer` | `prompts/test-spec-reviewer.md` | `{TEST_SPEC_PATH}` |
| `api-spec-writer` | `api-spec-reviewer` | `prompts/api-spec-reviewer.md` | `{API_SPEC_PATH}` |
| `infra-spec-writer` | `infra-spec-reviewer` | `prompts/infra-spec-reviewer.md` | `{INFRA_SPEC_PATH}` |
| `mock-writer` | `mock-reviewer` | `prompts/mock-reviewer.md` | `{MOCK_PATH}` |

reviewer は最終回答として `{"status":"approved"|"changes_requested","issues":[...]}` の JSON を返します。

### 3c. 修正ループ

| reviewer の結果 | 動作 |
|---|---|
| `approved` | そのドキュメントは完了 |
| `changes_requested` | `issues[]` を `SendMessage(to: "{writer name}")` で writer に渡して修正させ、完了後に同じ reviewer を再起動して再レビュー |
| JSON がパースできない | 回答本文を人間が読める形で保持し、明確な指摘があれば `changes_requested` として扱う |

1 ドキュメントあたりの修正ループは **最大 3 回**。超過したら残りの指摘を Phase 4 の人間レビューに持ち越します。

### 3d. 完了判定とリカバリ

起動したすべての reviewer が `approved`（または上限到達）になったら Phase 4 へ進みます。

通知が届かない場合（エージェントが途中でエラー終了した等）は、以下の手順でリカバリします：
1. 各ドキュメントファイル（TEST_SPEC_PATH / API_SPEC_PATH / INFRA_SPEC_PATH / MOCK_PATH）の存在を Bash で確認する
2. ファイルが存在すれば内容を Read して品質を直接確認し、問題なければ Phase 4 の人間レビューへ進む
3. ファイルが存在しなければ、該当する writer を同じ `name` で再起動して生成し直す

---

## Phase 4: 人間レビュー

AskUserQuestion ツールで以下を同時に提示してレビューを依頼：

- テスト定義書（TEST_SPEC_PATH）
- API仕様書（API_SPEC_PATH）（IS_API=true の場合）
- インフラ仕様書（INFRA_SPEC_PATH）（IS_INFRA=true の場合）
- モック HTML（MOCK_PATH）（IS_GUI=true の場合）— ブラウザで開いて確認するよう案内する

| 対象 | 結果 | 動作 |
|---|---|---|
| テスト定義書 | 修正が必要 | 指摘内容を `test-spec-writer` に SendMessage して再生成、完了後 `test-spec-reviewer` を再起動して再レビュー |
| API仕様書 | 修正が必要 | 指摘内容を `api-spec-writer` に SendMessage して再生成、完了後 `api-spec-reviewer` を再起動して再レビュー |
| モック | 修正が必要 | 指摘内容を `mock-writer` に SendMessage して再生成、完了後 `mock-reviewer` を再起動して再レビュー |
| インフラ仕様書 | 修正が必要 | 指摘内容を `infra-spec-writer` に SendMessage して再生成、完了後 `infra-spec-reviewer` を再起動して再レビュー |
| すべて承認 | — | 出力処理へ進む |

**SendMessage で再開できない場合（writer が破棄済み等）:**
Agent ツールで同じ `name` を使って新規起動し、修正依頼プロンプトを直接渡してください。
例: `Agent(name="test-spec-writer", run_in_background=true, model="sonnet", prompt="以下の指摘を反映して {TEST_SPEC_PATH} を修正してください: {指摘内容}。完了したら修正内容の要約を最終回答で返してください。")`

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
