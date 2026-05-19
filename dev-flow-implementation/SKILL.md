---
skill: dev-flow-implementation
description: 並列実装フェーズ（Phase 5）- git worktree でグループ並列実装 → 順次マージ
---


# Phase 5: 並列実装（git worktree ワークフロー）

## 入力

状態ファイル `doc/process/state.json` から読み込み：
- requirements_paths
- test_spec_path
- api_spec_path (IS_API=true の場合)
- mock_path (IS_GUI=true の場合)
- tech_stack
- is_gui
- is_api
- mode（`"full"` または `"incremental"`）
- baseline_commit（`incremental` 時のみ有効）

**モードによる動作の違い：**

| 項目 | full | incremental |
|---|---|---|
| 実装範囲 | チェックリストの全タスク | チェックリストのタスク（差分のみ・既にPhase 4.5で絞り込み済み） |
| 既存コードの扱い | 参照のみ（スタイル・規約を合わせる） | 必ず確認し、既存実装がある箇所はスキップ |
| dev/qa implementer モデル | `sonnet` | `sonnet` |

## 事前準備

### 5-pre-a: チェックリストの読み込みと再開判定

`doc/process/task_checklist.md` を Read ツールで読み込み、「並列実行グループ」セクションを解析します。

- グループ数を確認する（グループ 1、グループ 2、...）
- 各グループの Dev タスク・QA タスクを一覧化する
- **各グループのチーム種別（Infra / App / Cross）を抽出する**（グループ見出しから `(Infra)`, `(App)`, `(Cross)` を読み取る）

例: `### グループ 1 (Infra)` → `group_types["group-1"] = "Infra"`

次に `doc/process/state.json` を Read ツールで読み込み、`phase_5_progress` フィールドを確認します。

**`phase_5_progress` が存在する場合（前回の中断あり）:**

1. `completed_groups` を確認 → 完了済みグループはスキップ対象に記録
2. `active_worktrees` を確認 → 残存 worktree があれば以下でクリーンアップ：
   ```bash
   git worktree remove {MAIN_DIR}/../worktree-dev-group-N --force 2>/dev/null || true
   git worktree remove {MAIN_DIR}/../worktree-qa-group-N --force 2>/dev/null || true
   ```
3. AskUserQuestion で人間に確認：「グループ X から再開します。よろしいですか？」
   - 「再開する」→ 完了済みグループをスキップして処理継続
   - 「最初からやり直す」→ `phase_5_progress` を初期化して全グループを再実行

**`phase_5_progress` が存在しない場合（初回実行）:**

まず 5-pre-b でベースブランチを確認してから `phase_5_progress` を初期化します（base_branch が確定してから書き込むため）。

### 5-pre-b: ベースブランチの確認

```bash
git branch --show-current
```

現在のブランチ名を BASE_BRANCH として記録します。

その後 state.json に `phase_5_progress` を初期化して書き込みます：

```json
{
  "phase_5_progress": {
    "total_groups": {グループ数},
    "completed_groups": [],
    "active_worktrees": [],
    "base_branch": "{git branch --show-current の結果}",
    "group_types": {
      "group-1": "Infra",
      "group-2": "App",
      "group-3": "Cross"
    }
  }
}
```

`group_types` は 5-pre-a で抽出したチーム種別をすべて記録します

---

## Phase 5: グループ単位のループ

グループ 1 から順に以下を繰り返します。**グループ間は直列**（前グループのマージ完了後に次グループを開始）、**グループ内は並列**（Dev と QA を同時に worktree で実行）。

---

### STEP A: チーム種別判定と worktree の作成（グループ開始時）

`completed_groups` に含まれるグループは **スキップ** して次のグループへ進みます。

まず、`state.json` の `phase_5_progress.group_types["group-N"]` からグループのチーム種別を取得し、実行するエージェントを決定します：

| チーム種別 | 実行するエージェント | 説明 |
|---|---|---|
| `Infra` | Dev (Infra) + QA (Infra) のみ | アプリチームは起動しない |
| `App` | Dev (App) + QA (App) のみ | インフラチームは起動しない |
| `Cross` | Dev (Infra) → Dev (App) → QA (App) | インフラ実装完了後にアプリ実装を開始（直列） |

まず作業ディレクトリの絶対パスを確認します：

```bash
MAIN_DIR=$(pwd)
echo "メインディレクトリ: $MAIN_DIR"
```

グループ N のチーム種別に応じて必要な worktree のみ作成します：

**Infra グループの場合：**

```bash
# Dev (Infra) worktree
if git worktree list | grep -q "worktree-dev-infra-group-N"; then
  echo "Dev (Infra) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-dev-infra-group-N" -b dev/infra-group-N
fi

# QA (Infra) worktree
if git worktree list | grep -q "worktree-qa-infra-group-N"; then
  echo "QA (Infra) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-qa-infra-group-N" -b qa/infra-group-N
fi
```

**App グループの場合：**

```bash
# Dev (App) worktree
if git worktree list | grep -q "worktree-dev-app-group-N"; then
  echo "Dev (App) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-dev-app-group-N" -b dev/app-group-N
fi

# QA (App) worktree
if git worktree list | grep -q "worktree-qa-app-group-N"; then
  echo "QA (App) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-qa-app-group-N" -b qa/app-group-N
fi
```

**Cross グループの場合：**

```bash
# Dev (Infra) worktree
if git worktree list | grep -q "worktree-dev-infra-group-N"; then
  echo "Dev (Infra) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-dev-infra-group-N" -b dev/infra-group-N
fi

# Dev (App) worktree
if git worktree list | grep -q "worktree-dev-app-group-N"; then
  echo "Dev (App) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-dev-app-group-N" -b dev/app-group-N
fi

# QA (App) worktree
if git worktree list | grep -q "worktree-qa-app-group-N"; then
  echo "QA (App) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-qa-app-group-N" -b qa/app-group-N
fi
```

worktree 作成後、state.json の `phase_5_progress.active_worktrees` に作成したブランチ名を追加します（例: Infra なら `["dev/infra-group-N", "qa/infra-group-N"]`）。

---

### STEP B: チーム種別に応じたエージェント起動

グループのチーム種別に応じて、以下のパターンでエージェントを起動します：

**Infra グループ：Dev (Infra) + QA (Infra) を並列起動**

**App グループ：Dev (App) + QA (App) を並列起動**


### STEP B: チーム種別に応じたエージェント起動

グループのチーム種別に応じて、以下のパターンでエージェントを起動します：

**Infra グループ：Dev (Infra) + QA (Infra) を並列起動**

**App グループ：Dev (App) + QA (App) を並列起動**

**Cross グループ：Dev (Infra) → Dev (App) → QA (App) を順次起動**（インフラ実装完了を待ってからアプリ実装を開始）

各エージェントのプロンプトは以下のファイルを Read ツールで読み込んで使用します：

| エージェント | プロンプトファイル | 起動条件 |
|---|---|---|
| dev-implementer-infra-group-N | `~/.claude/skills/dev-flow-implementation/prompts/dev-infra.md` | Infra / Cross グループ |
| dev-implementer-app-group-N | `~/.claude/skills/dev-flow-implementation/prompts/dev-app.md` | App / Cross グループ |
| qa-implementer-infra-group-N | `~/.claude/skills/dev-flow-implementation/prompts/qa-infra.md` | Infra グループ |
| qa-implementer-app-group-N | `~/.claude/skills/dev-flow-implementation/prompts/qa-app.md` | App / Cross グループ |

プロンプトファイル内のプレースホルダー（`{GROUP_N}`, `{MAIN_DIR}`, `{MODE}` 等）を実際の値に置換してからエージェントに渡すこと。


---

### STEP C: エージェントの完了待機

グループのチーム種別に応じて、以下のメッセージを待ちます：

- **Infra**: `dev-infra-group-N 実装完了` + `qa-infra-group-N 実装完了`
- **App**: `dev-app-group-N 実装完了` + `qa-app-group-N 実装完了`
- **Cross**: `dev-infra-group-N 実装完了` → `dev-app-group-N 実装完了` → `qa-app-group-N 実装完了`（順次）

ブロッカー報告時は AskUserQuestion で人間に判断を仰ぐ。

---

### STEP D: レビュー

全エージェント完了後、チーム種別に応じてレビューを実行：

- **Infra**: Dev (Infra) → QA (Infra)
- **App**: Dev (App) → QA (App)
- **Cross**: Dev (Infra) → Dev (App) → QA (App)

各レビューは Agent（model=sonnet）で実行。指摘あり→修正→再レビュー（最大5回）。


---

### STEP E: PR作成

レビュー承認後、チーム種別に応じてブランチをpushしてPRを作成：

- **Infra**: `dev/infra-group-N`, `qa/infra-group-N` → label=`claude,infra`
- **App**: `dev/app-group-N`, `qa/app-group-N` → label=`claude,app`
- **Cross**: 上記3ブランチすべて → label=`claude,infra,cross` または `claude,app,cross`

PRタイトル例: `feat(infra): グループ N Infra Dev タスク実装`

---

### STEP F: worktreeクリーンアップ

PR作成後、worktreeを削除（ブランチは保持）：

```bash
git worktree remove {MAIN_DIR}/../worktree-{team}-group-N --force
```

---

### STEP G: マージ待機

AskUserQuestionで人間にPR URLを提示してマージ完了を確認。

- 「マージしました」→ STEP H へ
- 「修正が必要」→ worktreeを再作成して修正・再push後に再度待機

---

### STEP H: マージ後クリーンアップ

マージ確認後：

1. ローカル・リモートブランチを削除
2. `doc/process/task_checklist.md` のグループNタスクを `[x]` に更新
3. `doc/process/state.json` の `phase_5_progress` を更新（`completed_groups`に追加、`active_worktrees`をリセット）
4. 上記2ファイルを1コミットで記録

---

## 全グループ完了後

すべてのグループ完了後：

1. `doc/process/state.json` を更新：`current_phase` を `"phase_5"` に、`phase_5_progress` を削除
2. 人間に「Phase 5 完了。次は `/dev-flow` を実行して Phase 6 に進んでください」と通知

---

## エラーハンドリング

| 状況 | 対応 |
|---|---|
| worktree作成失敗 | 既存worktreeをクリーンアップ後に再試行 |
| push失敗 | 人間に報告して解消後に再push |
| lint エラー解消不可 | 人間に報告 |
| ブロッカー発生 | エージェント停止して人間に判断を仰ぐ |

