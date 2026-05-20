---
name: dev-flow-consistency
description: 整合性チェックフェーズ（Phase 4.5）を実行します。ドキュメント間の矛盾・考慮漏れを検出し、タスクチェックリストとスペックキャッシュを並列生成して設計を凍結します。mode=incrementalの場合は既存コードとの差分のみを抽出します。
---


# Phase 4.5: ドキュメント整合性チェックと設計凍結

## 入力

状態ファイル `doc/process/state.json` から読み込み：
- requirements_paths
- test_spec_path
- api_spec_path
- infra_spec_path
- mock_path
- tech_stack
- is_gui
- is_api
- is_infra
- mode（`"full"` または `"incremental"`）
- baseline_commit（`incremental` 時のみ有効）

## Phase 4.4: Impact Analysis（incremental mode 時のみ）

`mode = "incremental"` の場合のみ、Phase 4.5a の前に Impact Analysis を実行します。

以下のエージェントを起動（同期実行、`run_in_background=false`, `model="sonnet"`）：

```
あなたは Impact Analysis エージェントです。baseline_commit 以降のドキュメント変更を分析し、
影響を受ける実装箇所を ID ベースで特定してください。

baseline_commit: {BASELINE_COMMIT}

手順:
1. `git diff {BASELINE_COMMIT}..HEAD -- doc/` で変更されたドキュメントを確認
2. 変更された REQ-ID / TC-ID / API-ID を抽出
3. 各 ID に紐付く既存実装コードを特定（git log grep / find で探す）
4. 影響範囲をリスト化

出力フォーマット:
```
## Impact Analysis 結果

### 変更されたドキュメントノード
- REQ-002 (modified): "（変更内容の要約）"
- API-002 (modified): "（変更内容の要約）"
- TC-005 (added): "（追加内容の要約）"

### 影響を受ける実装
| 変更ID | 影響ファイル | 必要な変更 |
|---|---|---|
| REQ-002 | pkg/auth/validator.go | 最小文字数を 12 に変更 |
| API-002 | handlers/auth.go | リクエストスキーマ更新 |

### 影響を受けるタスク（チェックリスト用）
- [ ] task: （ファイル名）の（変更内容）（REQ-002）
```
```

Impact Analysis 完了後、その結果を Phase 4.5b（checklist-writer）に渡して、影響範囲のタスクのみをチェックリスト化させます。

---

## Phase 4.5a: ドキュメント整合性チェック

`mode` によって実行内容が異なります。

- **`mode = "full"`**: ドキュメント間の矛盾・考慮漏れを検出する（従来通り）
- **`mode = "incremental"`**: `baseline_commit` 以降に変更されたドキュメントと既存コードを比較し、「未実装の差分」を検出する（Phase 4.4 の Impact Analysis 結果を参考にする）

以下のエージェントを起動（同期実行、`run_in_background=false`, `model="opus"`）。

プロンプトは `prompts/consistency-check.md` を Read ツールで読み込み、プレースホルダー（`{MODE}`, `{BASELINE_COMMIT}`, `{REQUIREMENTS_PATHS}` 等）を実際の値に置換してから Agent に渡してください。

**重要:** `prompts/consistency-check.md` にmode別の詳細な手順が記載されています。このプロンプトファイルの指示に完全に従ってください。

---

## Phase 4.5b・4.5c: タスクチェックリストとスペックキャッシュの並列生成

TeamCreate で `consistency-team` を作成し、以下の2エージェントを同時に起動します。

```
TeamCreate(name: "consistency-team")
```

### タスクチェックリスト生成（`run_in_background=true`, `model="sonnet"`, `name="checklist-writer"`, `mode="acceptEdits"`）

プロンプトは `prompts/checklist-writer.md` を Read ツールで読み込み、プレースホルダー（`{MODE}`, `{BASELINE_COMMIT}`, `{REQUIREMENTS_PATHS}` 等）を実際の値に置換してから Agent に渡してください。

---

### スペックキャッシュ生成（`run_in_background=true`, `model="sonnet"`, `name="spec-cache-writer"`, `mode="acceptEdits"`）

プロンプトは `prompts/spec-cache-writer.md` を Read ツールで読み込み、プレースホルダー（`{MODE}`, `{BASELINE_COMMIT}`, `{REQUIREMENTS_PATHS}` 等）を実際の値に置換してから Agent に渡してください。

---

### consistency-orchestrator（`run_in_background=true`, `model="haiku"`, `name="consistency-orchestrator"`, `team_name="consistency-team"`）

---
`checklist-writer` からの「checklist 生成完了」通知と、`spec-cache-writer` からの「spec-cache 生成完了」通知を待ってください。
両方揃ったら、`SendMessage(to: "phase-consistency-agent", message: "consistency-team 完了")` で報告してください。

---

## Phase 4.5d: 設計凍結コミット

`consistency-team` の完了通知を受けたら、以下を実行。

通知が届かない場合（エージェントが途中でエラー終了した等）は、以下の手順でリカバリします：
1. `doc/process/task_checklist.md` と `doc/internal/spec_cache.md` の存在を Bash で確認する
2. 両ファイルが存在すれば内容を Read して品質を直接確認し、問題なければ Phase 4.5d へ進む
3. どちらかが存在しなければ、該当する writer を Agent で再起動して生成し直す

```bash
git add doc/
git commit -m "docs: freeze specifications"
```

これにより設計が物理的に固定されます。

---

## 出力

設計凍結コミット後、以下を実行：

1. `doc/process/state.json` を更新（current_phase を "phase_4_5" に）
2. 人間に「Phase 4.5 完了。次は `/dev-flow` を実行して Phase 5 に進んでください」と通知
