---
name: dev-flow-consistency
description: 整合性チェックフェーズ（Phase 4.5）を実行します。ドキュメント間の矛盾・考慮漏れを検出し、タスクチェックリストとスペックキャッシュを並列生成して設計を凍結します。mode=incrementalの場合は既存コードとの差分のみを抽出します。
---


# Phase 4.5: ドキュメント整合性チェックと設計凍結

## 実行モード

| モード | 用途 | state.json の current_phase |
|---|---|---|
| `full` | 通常（Phase 4.5 全体を実行） | `"phase_4"` |
| `incremental` | 要件追加時の差分チェック | `"phase_4"` + `mode="incremental"` |
| `mini` | Phase 5 中の Plan Repair 時（差分修正のみ） | `"phase_4_5_mini"` |

**`mini` モードの動作:**
- Phase 4.5a-pre（ID整合性）と Phase 4.5a（整合性チェック）はスキップ
- タスクチェックリストの**未着手グループのみ**を対象に checklist-writer を再実行（完了済みグループは保持）
- カバレッジ行列・スペックキャッシュは更新しない
- 完了後、state.json の `current_phase` を `"phase_4_5"` に戻す

---

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

`mode = "incremental"` の場合のみ、Phase 4.5a-pre の前に Impact Analysis を実行します。

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
- **`mode = "incremental"`**: `baseline_commit` 以降に変更されたドキュメントと既存コードを比較し、「未実装の差分」を検出する（Phase 4.4 の Impact Analysis 結果を参考にする）

以下のエージェントを起動（同期実行、`run_in_background=false`, `model="opus"`）。

プロンプトは `prompts/consistency-check.md` を Read ツールで読み込み、プレースホルダー（`{MODE}`, `{BASELINE_COMMIT}`, `{REQUIREMENTS_PATHS}` 等）を実際の値に置換してから Agent に渡してください。

**重要:** `prompts/consistency-check.md` にmode別の詳細な手順が記載されています。このプロンプトファイルの指示に完全に従ってください。

---

## Phase 4.5a-post: カバレッジ行列の生成

Phase 4.5a（整合性チェック）完了後、以下の手順で `doc/process/coverage_matrix.md` を生成します：

**フォーマット:**

```markdown
# カバレッジ行列

| 要件ID | 要件タイトル | テストID | API/エンドポイント | 実装タスク |
|---|---|---|---|---|
| REQ-001 | ユーザー認証 | TC-001, TC-002 | API-001 (POST /auth/login) | （Phase 4.5bのチェックリスト生成後に補完） |
| REQ-002 | パスワードリセット | TC-003 | API-002 | （同上） |
| REQ-003 | ログアウト | ❌ 未カバー | ❌ | ❌ |
```

**生成手順:**

1. 要件定義書の frontmatter から全 REQ-ID と要件タイトルを収集
2. テスト定義書の frontmatter から `test_cases[].covers` を読み取り、REQ-IDごとにTC-IDをマッピング
3. API仕様書の frontmatter から `endpoints[].covers` を読み取り、REQ-IDごとにAPI-IDをマッピング
4. 未カバーの REQ-ID（TC または API が空）を `❌ 未カバー` でマーク

**未カバー検出時の処理:**

未カバー要件が1件以上ある場合、AskUserQuestion で人間に判断を仰ぎます：

| 選択肢 | 動作 |
|---|---|
| 「要件を削除する」 | 要件定義書から該当 REQ-ID を削除し、frontmatter を更新 |
| 「テスト/APIを追加する」 | Phase 3 に戻ってドキュメントを補完（state.json の current_phase を "phase_2" に戻す） |
| 「このまま進める（除外範囲として認識）」 | coverage_matrix.md に `除外` と記録して続行 |

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
