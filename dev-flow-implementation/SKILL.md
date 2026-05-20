---
name: dev-flow-implementation
description: 並列実装フェーズ（Phase 5）を実行します。タスクチェックリストのグループを順次処理し、各グループ内でDev/QAを並列実装します。git worktreeで独立した作業環境を作成し、エージェントレビュー→PR作成→マージを繰り返します。Infra/App/Crossの3種類のチーム構成に対応します。
---


# Phase 5: 並列実装（git worktree ワークフロー）

## 入力

状態ファイル `doc/process/state.json` から読み込み：
- requirements_paths
- test_spec_path
- api_spec_path (IS_API=true の場合)
- infra_spec_path (IS_INFRA=true の場合)
- mock_path (IS_GUI=true の場合)
- tech_stack
- is_gui
- is_api
- is_infra
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
- **各グループの `depends_on` を抽出する**（例: `depends_on: [group-1, group-2]`）

例: `### グループ 1 (Infra) — depends_on: []` → `group_types["group-1"] = "Infra"`, `depends_on["group-1"] = []`

**DAGベース並列実行の初期化:**

`depends_on` を解析して実行可能グループを特定します：

- `depends_on` が空のグループ → **即時実行可能**
- `depends_on` に完了済みグループがすべて含まれるグループ → **実行可能**
- 上記以外 → **待機中**

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

## Phase 5: DAGベースのグループ実行ループ

DAGの依存関係に従って、実行可能なグループを並列に処理します。

**実行モデル:**
- **グループ間**: DAGベース並列（`depends_on` が解決済みのグループを同時に起動）
- **グループ内**: 並列（Dev と QA を同時に worktree で実行）

**実行アルゴリズム:**

```
while 未完了グループが存在する:
  実行可能グループ = depends_on が全て completed_groups に含まれるグループ
  実行可能グループ を並列に STEP A〜H まで起動（Background で複数グループ同時進行）
  いずれかのグループ完了 → completed_groups に追加
  次の実行可能グループを評価して追加起動
```

**state.json の `phase_5_progress` に `depends_on` マップを追加:**

```json
{
  "phase_5_progress": {
    "depends_on": {
      "group-1": [],
      "group-2": [],
      "group-3": ["group-1", "group-2"]
    }
  }
}
```

**worktree 構造:**
- Dev 用と QA 用で2本の worktree を作成（並列実行のため独立したブランチが必要）
- 例: Infra グループ → `dev/infra-group-N` と `qa/infra-group-N` の2ブランチ

---

### STEP A: チーム種別判定と worktree の作成（グループ開始時）

`completed_groups` に含まれるグループは **スキップ** して次のグループへ進みます。

まず、`state.json` の `phase_5_progress.group_types["group-N"]` からグループのチーム種別を取得し、実行するエージェントを決定します：

| チーム種別 | 実行するエージェント | 説明 |
|---|---|---|
| `Infra` | Dev (Infra) + QA (Infra) のみ | アプリチームは起動しない |
| `App` | Dev (App) + QA (App) のみ | インフラチームは起動しない |
| `Cross` | Dev (Infra) → QA (Infra) → Dev (App) → QA (App) | インフラ実装・テスト完了後にアプリ実装を開始（直列） |

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

# QA (Infra) worktree
if git worktree list | grep -q "worktree-qa-infra-group-N"; then
  echo "QA (Infra) worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/../worktree-qa-infra-group-N" -b qa/infra-group-N
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

worktree 作成後、state.json の `phase_5_progress.active_worktrees` に作成したブランチ名を追加します：
- Infra: `["dev/infra-group-N", "qa/infra-group-N"]`
- App: `["dev/app-group-N", "qa/app-group-N"]`
- Cross: `["dev/infra-group-N", "qa/infra-group-N", "dev/app-group-N", "qa/app-group-N"]`

---

### STEP B: チーム種別に応じたエージェント起動

グループのチーム種別に応じて、以下のパターンでエージェントを起動します：

**Infra グループ：Dev (Infra) + QA (Infra) を並列起動**

**App グループ：Dev (App) + QA (App) を並列起動**


### STEP B: チーム種別に応じたエージェント起動

グループのチーム種別に応じて、以下のパターンでエージェントを起動します：

**Infra グループ：Dev (Infra) + QA (Infra) を並列起動**

**App グループ：Dev (App) + QA (App) を並列起動**

**Cross グループ：Dev (Infra) → QA (Infra) → Dev (App) → QA (App) を順次起動**（インフラ実装・テスト完了を待ってからアプリ実装を開始）

各エージェントのプロンプトは以下のファイルを Read ツールで読み込んで使用します：

| エージェント | プロンプトファイル | 起動条件 |
|---|---|---|
| dev-implementer-infra-group-N | `~/.claude/skills/dev-flow-implementation/prompts/dev-infra.md` | Infra / Cross グループ |
| dev-implementer-app-group-N | `~/.claude/skills/dev-flow-implementation/prompts/dev-app.md` | App / Cross グループ |
| qa-implementer-infra-group-N | `~/.claude/skills/dev-flow-implementation/prompts/qa-infra.md` | Infra グループ |
| qa-implementer-app-group-N | `~/.claude/skills/dev-flow-implementation/prompts/qa-app.md` | App / Cross グループ |

プロンプトファイル内のプレースホルダー（`{GROUP_N}`, `{MAIN_DIR}`, `{MODE}` 等）を実際の値に置換してからエージェントに渡すこと。

**ファイルスコープガードレール:**

各エージェントには**作業対象ファイルパスの制約**を明示してプロンプトに含めること：

| エージェント | 作業許可ディレクトリ | 禁止ディレクトリ例 |
|---|---|---|
| Dev (Infra) | `{MAIN_DIR}/../worktree-dev-infra-group-N/` 配下のインフラ関連ファイル | フロントエンド、アプリ層 |
| Dev (App) | `{MAIN_DIR}/../worktree-dev-app-group-N/` 配下のアプリ関連ファイル | Terraform、インフラ設定 |
| QA (Infra) | `{MAIN_DIR}/../worktree-qa-infra-group-N/` 配下のインフラテスト | アプリテスト |
| QA (App) | `{MAIN_DIR}/../worktree-qa-app-group-N/` 配下のアプリテスト | インフラテスト |

**プロンプトに追記する文言:**

```
【ファイルスコープ制限】
担当タスク（{DEV/QA_TASKS}）に直接関係するファイルのみ変更すること。
- 許可: {作業許可ディレクトリのパターン}（例: `*.tf`, `pkg/auth/**`, `tests/auth/**`）
- 禁止: 担当範囲外のファイル（例: フロントエンド、他チームのモジュール）

タスクに関係ないファイルを変更しそうになった場合は変更せず、代わりに SendMessage で "ファイルスコープ外の変更が必要" と報告してください。
```

---

### STEP C: エージェントの完了待機

グループのチーム種別に応じて、以下のメッセージを待ちます：

- **Infra**: `dev-infra-group-N 実装完了` + `qa-infra-group-N 実装完了`
- **App**: `dev-app-group-N 実装完了` + `qa-app-group-N 実装完了`
- **Cross**: `dev-infra-group-N 実装完了` → `qa-infra-group-N 実装完了` → `dev-app-group-N 実装完了` → `qa-app-group-N 実装完了`（順次）

ブロッカー報告時は AskUserQuestion で人間に判断を仰ぐ。

---

### STEP D: レビュー

全エージェント完了後、チーム種別に応じてレビューを実行。各レビューは独立したエージェント（model=sonnet）で実行します。

**実行順序：**
- **Infra**: Dev (Infra) レビュー → QA (Infra) レビュー
- **App**: Dev (App) レビュー → QA (App) レビュー
- **Cross**: Dev (Infra) レビュー → QA (Infra) レビュー → Dev (App) レビュー → QA (App) レビュー

#### Dev (Infra) レビュー（Infra / Cross グループ）

Agent を起動（同期実行、`run_in_background=false`, `model="sonnet"`）：

```
あなたは Infra Dev チームのシニアエンジニア（レビュアー）です。

対象 worktree: {MAIN_DIR}/../worktree-dev-infra-group-N
要件定義書: {REQUIREMENTS_PATHS}
インフラ仕様書: {INFRA_SPEC_PATH}
技術スタック: {tech_stack}

**重要: 読み取り専用。ファイル変更不可。**

worktree 内の実装ファイルを Read して以下を確認：
- 要件充足・セキュリティ・パフォーマンス・可読性

指摘あり → 具体的な修正箇所と理由を報告
指摘なし → 「承認」と報告
```

指摘あり → dev-implementer-infra-group-N を再起動して修正（最大5回）

#### Dev (App) レビュー（App / Cross グループ）

同様に App Dev のシニアレビュアーエージェントを起動。

#### QA (Infra) レビュー（Infra / Cross グループ）

Infra QA のシニアレビュアーエージェントを起動。テスト網羅性・独立性を確認。

#### QA (App) レビュー（App / Cross グループ）

App QA のシニアレビュアーエージェントを起動。テスト網羅性・独立性を確認。


---

### STEP E: PR作成

レビュー承認後、チーム種別に応じてブランチをpushしてPRを作成：

- **Infra**: `dev/infra-group-N`, `qa/infra-group-N` → 2PR作成、label=`infra`
- **App**: `dev/app-group-N`, `qa/app-group-N` → 2PR作成、label=`app`
- **Cross**: 4ブランチすべて → 4PR作成、Infraブランチには`infra,cross`、Appブランチには`app,cross`

PRタイトル例: 
- `feat(infra): グループ N Infra Dev タスク実装`
- `test(infra): グループ N Infra QA タスク実装`

---

### STEP F: worktreeクリーンアップ

PR作成後、worktreeを削除（ブランチは保持）：

**Infra / App:**
```bash
git worktree remove {MAIN_DIR}/../worktree-dev-{team}-group-N --force
git worktree remove {MAIN_DIR}/../worktree-qa-{team}-group-N --force
```

**Cross:**
```bash
git worktree remove {MAIN_DIR}/../worktree-dev-infra-group-N --force
git worktree remove {MAIN_DIR}/../worktree-qa-infra-group-N --force
git worktree remove {MAIN_DIR}/../worktree-dev-app-group-N --force
git worktree remove {MAIN_DIR}/../worktree-qa-app-group-N --force
```

---

### STEP G: マージ待機

AskUserQuestionで人間にPR URLを提示してマージ完了を確認。

- 「マージしました」→ STEP H へ
- 「修正が必要」→ worktreeを再作成して修正・再push後に再度待機

---

### STEP H: マージ後クリーンアップ

マージ確認後：

1. ローカル・リモートブランチを削除：
   - Infra: `dev/infra-group-N`, `qa/infra-group-N`
   - App: `dev/app-group-N`, `qa/app-group-N`
   - Cross: 上記4ブランチすべて
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

