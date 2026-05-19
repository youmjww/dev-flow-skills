---
skill: dev-flow
description: AI駆動開発フロー - 軽量オーケストレーター（サブエージェント経由でフェーズスキルを実行する）
---

# 開発フローオーケストレーター

あなたは開発フローの**メインオーケストレーター**です。状態ファイルを管理し、各フェーズのスキルをサブエージェント経由で順次実行してフローを進めます。

---

## 状態管理

### 状態ファイル: `doc/process/state.json`

```json
{
  "current_phase": "phase_2",
  "mode": "full",
  "baseline_commit": null,
  "requirements_paths": ["doc/requirements/feature.md"],
  "test_spec_path": "doc/test-spec/feature.md",
  "api_spec_path": "doc/api-spec/feature.md",
  "mock_path": "doc/mock/feature.html",
  "tech_stack": {
    "language": "Go",
    "framework": "Gin",
    "test_framework": "testing",
    "db": "PostgreSQL",
    "linter": "golangci-lint",
    "formatter": "gofmt",
    "e2e_framework": null
  },
  "is_gui": false,
  "is_api": true,
  "is_e2e": false,
  "from": "requirements",
  "phase_5_progress": {
    "total_groups": 2,
    "completed_groups": ["group-1"],
    "active_worktrees": [],
    "base_branch": "feature/xxx"
  }
}
```

- `mode`: `"full"`（新規開発）または `"incremental"`（要件追加による差分のみ実装）
- `baseline_commit`: `incremental` 時のみ設定。要件追加前の最新コミットハッシュ。Phase 4.5 でここを基点にドキュメントと既存コードの差分を検出する
- `phase_5_progress` は Phase 5 実行中のみ存在し、Phase 5 完了時に削除されます。

---

## フロー実行

### STEP 1: 引数の解析

`{{ARGS}}` を解析：

- **TASK**: タスクの説明（`--` で始まらない部分）
- **FROM**: 開始フェーズ（`--from=` の値）
  - 指定あり → state.json の current_phase を無視して指定フェーズから強制開始（state.json が必要）
  - 指定なし → STEP 2 の current_phase に従う

`--from` の値と対応フェーズ：

| `--from` 値 | 開始フェーズ | state.json 要否 |
|---|---|---|
| `requirements` または 未指定かつ state.json なし | Phase 1 | 不要 |
| `spec` | Phase 3 | 必要 |
| `parallel` | Phase 5 | 必要 |
| `test` | Phase 6 | 必要 |
| `sync` | Phase 7 | 必要 |

`--from` 指定時に state.json が存在しない場合は AskUserQuestion で人間にエラーを報告する。

### STEP 1.5: 開発モードの判定（state.json が存在しない場合のみ）

STEP 1 の後、STEP 2 の state.json 読み込み前に実行します。  
**state.json が存在する場合はスキップ**（既存フローの継続のため、mode は state.json の値を使う）。

**1. 既存実装の確認：**

```bash
git log --oneline -1 2>/dev/null
ls app/ terraform/ src/ backend/ frontend/ 2>/dev/null | head -5
```

**2. 既存コミットと実装コードが両方存在する場合：**

AskUserQuestion で確認：

| 選択肢 | 意味 |
|---|---|
| 新規開発（ゼロから全機能実装） | ドキュメント生成→全機能実装 |
| 要件追加（既存実装への差分のみ追加） | ドキュメントvs既存コードの差分のみ実装 |

**3. モードの確定とメモリへの記録：**

| 状況 | mode | baseline_commit |
|---|---|---|
| 「新規開発」を選択 | `"full"` | `null` |
| 「要件追加」を選択 | `"incremental"` | `git rev-parse HEAD` の結果 |
| 既存コミットなし / 実装コードなし | `"full"`（自動確定） | `null` |

確定した `mode` と `baseline_commit` はこのステップ後のすべての処理に引き継ぎます。

---

### STEP 2: 状態ファイルの読み込み

`doc/process/state.json` が存在する場合、Read ツールで読み込んで `current_phase` を確認します。

- 存在する → current_phase から次フェーズを決定（ただし STEP 1 の `--from` 引数が指定されている場合はそちらを優先）。`mode` と `baseline_commit` も読み込む
- 存在しない → Phase 1（要件定義）から開始。`mode` と `baseline_commit` は STEP 1.5 で確定した値を使う

### STEP 3: タスクチェックリストの確認・表示

`doc/process/task_checklist.md` が存在する場合、Read ツールで読み込み、現在の進捗を人間に表示します：

```
## 現在の進捗
{チェックリストの「フェーズ進捗」セクションを表示}
```

ファイルが存在しない場合（Phase 4.5 以前）はスキップします。

### STEP 4: タスクを作成してサブエージェントを起動

実行するフェーズに対応するタスクを **TaskCreate** で作成してから、サブエージェントを起動します。

| current_phase | タスク名 | エージェント name | モデル | 使用するスキルファイル |
|---|---|---|---|---|
| なし（初回） | Phase 1-2: 要件定義 | `phase-requirements-agent` | opus | `~/.claude/skills/dev-flow-requirements/SKILL.md` |
| phase_2 | Phase 3-4: ドキュメント生成 | `phase-spec-agent` | haiku | `~/.claude/skills/dev-flow-spec/SKILL.md` |
| phase_4 | Phase 4.5: 整合性チェック | `phase-consistency-agent` | haiku | `~/.claude/skills/dev-flow-consistency/SKILL.md` |
| phase_4_5 | Phase 5: 並列実装 | `phase-impl-agent` | haiku | `~/.claude/skills/dev-flow-implementation/SKILL.md` |
| phase_5 | Phase 6: テスト実行 | `phase-test-agent` | haiku | `~/.claude/skills/dev-flow-test/SKILL.md` |
| phase_6 | Phase 7-8: 準拠チェック・完了 | `phase-compliance-agent` | opus | `~/.claude/skills/dev-flow-compliance/SKILL.md` |

**タスク作成:**

サブエージェントを起動する前に TaskCreate でタスクを作成し、ステータスを `in_progress` にします：

```
TaskCreate(
  name: "{タスク名}",
  description: "dev-flow: {タスク名} を実行中"
)
TaskUpdate(id: "{task_id}", status: "in_progress")
```

**サブエージェント起動方法:**

Agent ツールを使って以下のプロンプトでサブエージェントを起動します（同期実行: `run_in_background=false`）。**必ず上表の `name` と `model` を指定すること**（name がないと SendMessage のルーティングが失敗する）：

```
Agent(
  name: "{エージェント name}",
  model: "{モデル}",
  run_in_background: false,
  prompt: """
Read ツールで {スキルファイルパス} を読み込み、そこに書かれた指示を完全に実行してください。

作業ディレクトリ: {現在の作業ディレクトリ（Bash で pwd して確認すること）}
状態ファイル: doc/process/state.json
引数: {ARGS の内容}
開発モード: {mode}（"full" = 新規開発 / "incremental" = 要件追加による差分のみ）
baseline_commit: {baseline_commit}（incremental 時のみ有効。null の場合は無視してよい）

スキルファイルを読んだら、その指示に従って作業を進めてください。
"""
)
```

### STEP 5: タスク完了 & チェックリスト更新 & 完了通知

サブエージェント完了後、以下を順に実行します：

**1. TaskUpdate で完了にする:**

```
TaskUpdate(id: "{task_id}", status: "completed")
```

**2. チェックリストのフェーズ進捗を更新:**

`doc/process/task_checklist.md` が存在する場合、完了したフェーズ行の `[ ]` を `[x]` に更新します：

| 完了したフェーズ | 更新する行 |
|---|---|
| Phase 5 完了（phase_4_5 → phase_5） | `- [ ] Phase 5: 並列実装（Dev / QA）` → `[x]` |
| Phase 6 完了（phase_5 → phase_6） | `- [ ] Phase 6: テスト実行` → `[x]` |
| Phase 7-8 完了 | `- [ ] Phase 7-8: ドキュメント準拠チェック・完了` → `[x]` |

更新後、チェックリストの「フェーズ進捗」セクションを人間に表示して進捗を確認させます。

**3. 人間への案内:**

```
Phase X 完了。次は `/dev-flow` を実行して Phase Y に進んでください。
```

---

## フローの全体像

```
/dev-flow (初回)
  ↓ TaskCreate("Phase 1-2: 要件定義") → in_progress
  ↓ Agent(name="phase-requirements-agent", model="opus")
Phase 1-2: 要件定義
  → state.json 保存（phase_2） → TaskUpdate(completed)
  ↓
/dev-flow
  ↓ [チェックリストなし → STEP 3 スキップ]
  ↓ TaskCreate("Phase 3-4: ドキュメント生成") → in_progress
  ↓ Agent(name="phase-spec-agent", model="haiku")
Phase 3-4: ドキュメント生成
  doc-orchestrator → SendMessage(to: "phase-spec-agent", "doc-team 全レビュー完了")
  → state.json 保存（phase_4） → TaskUpdate(completed)
  ↓
/dev-flow
  ↓ [チェックリストなし → STEP 3 スキップ]
  ↓ TaskCreate("Phase 4.5: 整合性チェック") → in_progress
  ↓ Agent(name="phase-consistency-agent", model="haiku")
Phase 4.5: 整合性チェック（チェックリスト生成）
  consistency-orchestrator → SendMessage(to: "phase-consistency-agent", "consistency-team 完了")
  → state.json 保存（phase_4_5） → TaskUpdate(completed)
  → checklist フェーズ進捗: 1-2/3-4/4.5 = [x], 5/6/7-8 = [ ]
  ↓
/dev-flow
  ↓ [STEP 3: チェックリスト進捗を表示]
  ↓ TaskCreate("Phase 5: 並列実装") → in_progress
  ↓ Agent(name="phase-impl-agent", model="haiku")
Phase 5: 並列実装（git worktree でグループ並列）
  グループ N ごとに:
    worktree 作成 → Dev/QA 並列実装
    dev/qa-implementer → SendMessage(to: "phase-impl-agent", "dev/qa-group-N 実装完了")
    → エージェントレビュー → PR 作成 → worktree 削除
    → 人間レビュー・マージ待機 → ブランチ削除
    → checklist + state.json(phase_5_progress) を1コミットで更新
  → state.json 保存（phase_5、phase_5_progress 削除） → TaskUpdate(completed)
  → checklist: Phase 5 → [x]（orchestrator が STEP 5 で更新）
  ↓
/dev-flow
  ↓ [STEP 3: チェックリスト進捗を表示]
  ↓ TaskCreate("Phase 6: テスト実行") → in_progress
  ↓ Agent(name="phase-test-agent", model="haiku")
Phase 6: テスト実行
  → state.json 保存（phase_6） → TaskUpdate(completed)
  → checklist: Phase 6 → [x]
  ↓
/dev-flow
  ↓ [STEP 3: チェックリスト進捗を表示]
  ↓ TaskCreate("Phase 7-8: 準拠チェック・完了") → in_progress
  ↓ Agent(name="phase-compliance-agent", model="opus")
Phase 7-8: 準拠チェック・完了
  → state.json 削除 → TaskUpdate(completed)
  → checklist: Phase 7-8 → [x] → 完了
```

---

## エラーハンドリング

- サブエージェント実行中にエラーが発生した場合は、人間に状況を報告して指示を仰ぐ
- 状態ファイルが破損している場合は、人間に確認して再作成するか、最初からやり直すか選択させる
- スキルファイルが見つからない場合は、`~/.claude/skills/` 配下の `dev-flow-*` ディレクトリを列挙して確認する

