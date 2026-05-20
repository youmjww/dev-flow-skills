---
name: dev-flow
description: AI駆動開発フローを管理します。サブエージェント経由で要件定義→ドキュメント生成→整合性チェック→並列実装→テスト→準拠チェックの各フェーズを順次実行します。/dev-flow コマンドで起動します。
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
  "infra_spec_path": "doc/infra-spec/feature.md",
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
  "is_infra": true,
  "is_e2e": false,
  "from": "requirements",
  "phase_5_progress": {
    "total_groups": 3,
    "completed_groups": ["group-1"],
    "active_worktrees": [],
    "base_branch": "feature/xxx",
    "group_types": {
      "group-1": "Infra",
      "group-2": "App",
      "group-3": "Cross"
    }
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

オーケストレーターが**スキルファイルを事前に Read**して要点をまとめ、サブエージェントにはその要点を直接プロンプトとして渡します（サブエージェント側の再 Read を不要にすることでトークン消費とレイテンシを削減）。

手順:
1. スキルファイルを Read ツールで読み込む
2. フェーズに必要な手順のみを抽出してプロンプトに埋め込む
3. Agent を起動する

```
# 1. 事前にスキルファイルを読み込む
スキル内容 = Read({スキルファイルパス})

# 2. サブエージェントを起動（スキル内容を直接渡す）
Agent(
  name: "{エージェント name}",
  model: "{モデル}",
  run_in_background: false,
  prompt: """
あなたは {フェーズ名} を担当するエージェントです。以下の指示に従って作業を完全に実行してください。

作業ディレクトリ: {現在の作業ディレクトリ（Bash で pwd して確認すること）}
状態ファイル: doc/process/state.json
引数: {ARGS の内容}
開発モード: {mode}（"full" = 新規開発 / "incremental" = 要件追加による差分のみ）
baseline_commit: {baseline_commit}（incremental 時のみ有効。null の場合は無視してよい）

## 実行する手順

{スキル内容の該当フェーズ手順をここに直接埋め込む}
"""
)
```

**フォールバック**: スキルファイルのサイズが大きくプロンプトに収まらない場合は、従来通り Read ツールでの読み込みを指示するが、その場合もフェーズに関係ないセクション（フロー全体像など）は省略するよう指示すること。

### STEP 5: タスク完了 & チェックリスト更新 & 次フェーズへの移行判定

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

**3. 次フェーズへの自動移行判定:**

以下の移行ルールに従って、次のフェーズを自動実行するか人間の確認を待つか判定します：

| 完了フェーズ | 次フェーズ | 動作 |
|---|---|---|
| phase_2（Phase 1-2: 要件定義） | phase_2 → Phase 3-4 | **手動確認**：人間に「要件定義が完了しました。内容を確認してから `/dev-flow` を実行してください。」と案内 |
| phase_4（Phase 3-4: ドキュメント生成） | phase_4 → Phase 4.5 | **自動移行**：STEP 2 に戻って Phase 4.5 を自動実行 |
| phase_4_5（Phase 4.5: 整合性チェック） | phase_4_5 → Phase 5 | **自動移行**：STEP 2 に戻って Phase 5 を自動実行 |
| phase_5（Phase 5: 並列実装） | phase_5 → Phase 6 | **自動移行**：STEP 2 に戻って Phase 6 を自動実行 |
| phase_6（Phase 6: テスト実行） | phase_6 → Phase 7-8 | **自動移行**：STEP 2 に戻って Phase 7-8 を自動実行 |

**自動移行時の処理:**

自動移行する場合は、以下の手順で次フェーズを実行します：

1. 人間に簡潔な進捗報告を出力（例：「Phase 3-4 完了。Phase 4.5 を自動開始します。」）
2. STEP 2 に戻って state.json を再読み込み
3. STEP 3 でチェックリスト進捗を表示（存在する場合）
4. STEP 4 で次フェーズのサブエージェントを起動
5. STEP 5 で完了判定（次フェーズも自動移行対象なら繰り返し）

**重要:** 自動移行は再帰的に実行されます。つまり、Phase 3-4 完了後は Phase 4.5 → Phase 5 → Phase 6 → Phase 7-8 まで連続して自動実行されます（Phase 5 の各グループのPRマージ待機を除く）。

**手動確認時の処理:**

手動確認が必要な場合（Phase 1-2 完了時のみ）は、以下のメッセージを出力して終了します：

```
Phase 1-2 完了。要件定義の内容を確認してから `/dev-flow` を実行してください。
```

---

## フローの全体像

```
/dev-flow (初回)
  ↓ TaskCreate("Phase 1-2: 要件定義") → in_progress
  ↓ Agent(name="phase-requirements-agent", model="opus")
Phase 1-2: 要件定義
  → state.json 保存（phase_2） → TaskUpdate(completed)
  → ✋ 手動確認待ち（要件定義の承認）
  ↓
/dev-flow（人間が実行）
  ↓ [チェックリストなし → STEP 3 スキップ]
  ↓ TaskCreate("Phase 3-4: ドキュメント生成") → in_progress
  ↓ Agent(name="phase-spec-agent", model="haiku")
Phase 3-4: ドキュメント生成
  doc-orchestrator → SendMessage(to: "phase-spec-agent", "doc-team 全レビュー完了")
  → state.json 保存（phase_4） → TaskUpdate(completed)
  → 🤖 自動移行: STEP 2 へ戻る
  ↓
  ↓ [チェックリストなし → STEP 3 スキップ]
  ↓ TaskCreate("Phase 4.5: 整合性チェック") → in_progress
  ↓ Agent(name="phase-consistency-agent", model="haiku")
Phase 4.5: 整合性チェック（チェックリスト生成）
  consistency-orchestrator → SendMessage(to: "phase-consistency-agent", "consistency-team 完了")
  → state.json 保存（phase_4_5） → TaskUpdate(completed)
  → checklist フェーズ進捗: 1-2/3-4/4.5 = [x], 5/6/7-8 = [ ]
  → 🤖 自動移行: STEP 2 へ戻る
  ↓
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
  → 🤖 自動移行: STEP 2 へ戻る
  ↓
  ↓ [STEP 3: チェックリスト進捗を表示]
  ↓ TaskCreate("Phase 6: テスト実行") → in_progress
  ↓ Agent(name="phase-test-agent", model="haiku")
Phase 6: テスト実行
  → state.json 保存（phase_6） → TaskUpdate(completed)
  → checklist: Phase 6 → [x]
  → 🤖 自動移行: STEP 2 へ戻る
  ↓
  ↓ [STEP 3: チェックリスト進捗を表示]
  ↓ TaskCreate("Phase 7-8: 準拠チェック・完了") → in_progress
  ↓ Agent(name="phase-compliance-agent", model="opus")
Phase 7-8: 準拠チェック・完了
  → state.json 削除 → TaskUpdate(completed)
  → checklist: Phase 7-8 → [x] → 完了
```

**凡例:**
- ✋ 手動確認待ち: 人間が `/dev-flow` を実行するまで待機
- 🤖 自動移行: STEP 2 に戻って次フェーズを自動実行

---

## エラーハンドリング

### 状態ファイル関連

**state.json が破損している場合:**
1. `doc/process/state.json` のバックアップを確認：
   ```bash
   git log --oneline -- doc/process/state.json | head -5
   ```
2. 最新コミットから復元を試みる：
   ```bash
   git show HEAD:doc/process/state.json
   ```
3. 復元不可の場合は AskUserQuestion で人間に選択を求める：
   - 「最初からやり直す（Phase 1から）」
   - 「手動で state.json を修正する」

**state.json の必須フィールドが欠損している場合:**
- `current_phase` が不明 → 人間に現在のフェーズを確認
- `mode` が不明 → デフォルトで `"full"` を設定
- `requirements_paths` が空 → `doc/requirements/*.md` を列挙して確認

### サブエージェント関連

**Agent ツールの起動に失敗した場合:**
1. スキルファイルパスの存在を Bash で確認：
   ```bash
   ls -la ~/.claude/skills/dev-flow-*/SKILL.md
   ```
2. スキルファイルが見つからない場合は、`~/.claude/skills/` 配下の `dev-flow-*` ディレクトリを列挙
3. 3回連続で失敗したら人間に報告して中断

**サブエージェントが途中で停止した場合:**
- エージェントの最終出力を確認
- SendMessage の通知が届かない場合は、該当フェーズの成果物（ドキュメントファイル等）の存在を Bash で確認
- 成果物が存在すれば Read して品質を直接確認し、問題なければ次フェーズへ進む
- 成果物が存在しなければ、同じ設定でサブエージェントを再起動（最大2回）

### チェックリスト関連

**task_checklist.md の更新に失敗した場合:**
- Edit ツールのエラーメッセージを確認
- `old_string` が見つからない場合は、Read で現在の内容を再確認してから更新
- 3回失敗したら人間に報告（手動更新を依頼）

### その他

**--from 引数が不正な場合:**
- 有効な値（`requirements`, `spec`, `parallel`, `test`, `sync`）を AskUserQuestion で提示
- 人間が選択した値で再実行

**予期しないエラー:**
- エラーメッセージ・スタックトレース・関連ファイルパスを含めて人間に報告
- 可能であれば復旧手順を提案（例：「Phase X から再実行してください」）

