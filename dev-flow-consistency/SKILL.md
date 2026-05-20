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

## Phase 4.5a-pre: トレーサビリティID整合性チェック

整合性チェック（Phase 4.5a）の前に、以下のID参照チェックを実施してください：

**1. 要件ID一覧の抽出:**

要件定義書（全ファイル）の frontmatter から `requirements[].id`（REQ-NNN）を収集し、マスターリストを作成します。

**2. 参照先の存在チェック:**

| チェック対象 | 確認事項 |
|---|---|
| テスト定義書 `test_cases[].covers` | すべての REQ-NNN がマスターリストに存在するか |
| API仕様書 `endpoints[].covers` | すべての REQ-NNN がマスターリストに存在するか |
| テスト定義書ルートの `covers` | すべての REQ-NNN がマスターリストに存在するか |

**3. 未参照REQ-IDの検出:**

マスターリストのREQ-IDのうち、どのドキュメントの `covers` にも登場しないものを「未カバー要件」として記録します（Phase 4.5 でカバレッジ行列に反映）。

**4. エラー処理:**

- 存在しないIDへの参照 → AskUserQuestion で人間に修正を依頼（続行不可）
- frontmatter が存在しないドキュメント → 警告を記録して Phase 4.5a に進む（ブロックしない）

---

## Phase 4.5a: ドキュメント整合性チェック

`mode` によって実行内容が異なります。

- **`mode = "full"`**: ドキュメント間の矛盾・考慮漏れを検出する（従来通り）
- **`mode = "incremental"`**: `baseline_commit` 以降に変更されたドキュメントと既存コードを比較し、「未実装の差分」を検出する

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
両方揃ったら、以下の JSON で報告してください：

```
SendMessage(
  to: "phase-consistency-agent",
  message: '{"agent":"consistency-orchestrator","status":"completed","result":{"generated":["task_checklist","spec_cache"]},"blockers":[]}'
)
```

パース失敗に備えたフォールバックとして、JSON が生成できない場合は `"consistency-team 完了"` のフリーテキストで送信してください。

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
