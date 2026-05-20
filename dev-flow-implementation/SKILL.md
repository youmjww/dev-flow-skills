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

**過去のレビュー指摘・テスト失敗パターンの注入:**

各エージェントを起動する前に、プロジェクトの memory ディレクトリから関連する feedback を読み込んでプロンプト冒頭に注入します：

```bash
# memory ディレクトリを確認
MEMORY_DIR="~/.claude/projects/$(pwd | sed 's|/|-|g')/memory"
ls "${MEMORY_DIR}/feedback_review_infra.md" 2>/dev/null
ls "${MEMORY_DIR}/feedback_review_app.md" 2>/dev/null
ls "${MEMORY_DIR}/feedback_test_failures.md" 2>/dev/null
```

ファイルが存在する場合、プロンプトの先頭に以下を追記：

```
## 過去のレビューで指摘された再発項目（必ず確認してから実装・レビューすること）

{feedback_review_infra.md または feedback_review_app.md の内容}
```

**レビュー指摘・テスト失敗のmemory保存（STEP D/STEP H後）:**

レビュー指摘が3回以上繰り返されたパターンまたは人間によるマージ後修正があった場合、以下のフォーマットで memory に保存します：

```markdown
---
name: feedback-review-infra-{date}
description: Infra レビューで再発する指摘パターン（{date} 記録）
metadata:
  type: feedback
---

## 再発指摘パターン

- **{指摘カテゴリ}**: {具体的な指摘内容}
  - 発生回数: {N}回
  - 典型例: {コード例または説明}
  - 対処方法: {推奨する実装アプローチ}
```

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

**昇格ラダー（Dev/QA implementer）:**

| 段階 | モデル | 試行 | 昇格条件 |
|---|---|---|---|
| 初回実装 | `haiku` | 1回 | 完了 → レビューへ |
| 修正実装（Haiku） | `haiku` | 最大2回 | レビュー指摘が設計レベルと判定 → Sonnet 昇格 |
| 修正実装（Sonnet） | `sonnet` | 最大3回 | 上限到達 → 人間エスカレーション |

**Sonnet 昇格時のプロンプト冒頭に以下を追記する:**

```
【モデル昇格通知】
Haiku による修正試行が上限に達したか、設計レベルの指摘が含まれるため Sonnet に昇格しました。
以下のレビュー指摘履歴を参考に、より高度な判断で問題を解決してください。

### Haiku 試行履歴
{Haiku の試行回数と主な失敗内容}

### 未解決の指摘
{レビュアーからの指摘内容}
```

タスク種別による初期モデルの選択：
- CRUD 追加・設定変更など単純タスク → `haiku` で開始
- 新規アーキテクチャ要素・横断的な変更 → `sonnet` で開始（state.json の `task_complexity` フィールドで制御。未設定の場合は `haiku` で開始）

---

### STEP C: エージェントの完了待機

グループのチーム種別に応じて、各エージェントからの SendMessage を待ちます：

- **Infra**: `dev-implementer-infra-group-N` + `qa-implementer-infra-group-N` の両方
- **App**: `dev-implementer-app-group-N` + `qa-implementer-app-group-N` の両方
- **Cross**: `dev-implementer-infra-group-N` → `qa-implementer-infra-group-N` → `dev-implementer-app-group-N` → `qa-implementer-app-group-N`（順次）

**JSON パース処理:**

受信したメッセージを JSON としてパースし、`status` フィールドで以下の通り分岐します：

| status | blocker_type | 対応 |
|---|---|---|
| `"completed"` | — | `result.commits` をログに記録して次の処理へ進む |
| `"blocked"` | `"plan_repair_needed"` | **Plan Repair フローへ移行**（下記参照） |
| `"blocked"` | その他 | AskUserQuestion で人間に判断を仰ぐ |
| `"failed"` | — | AskUserQuestion で人間に報告し指示を仰ぐ |

**Plan Repair フロー（`blocker_type: "plan_repair_needed"` 受信時）:**

Plan Repair の発動は同一フロー内で最大3回まで。上限到達後は `plan_repair_needed` を `requirement_ambiguity` として処理（人間にエスカレーション）。

1. 現在進行中の worktree の作業状況をメモ（`state.json` の `phase_5_progress.plan_repair_memo` に記録）
2. AskUserQuestion で人間に提示：

```
## 計画修正リクエスト

エージェント: {agent}
理由: {reason}

提案された修正:
{suggested_repair を表示}

どのように対処しますか？
```

| 選択肢 | 動作 |
|---|---|
| 「計画修正を承認」 | Phase 4.5 を mini モードで再実行（差分修正のみ） |
| 「却下して当初計画で続行」 | そのまま Phase 5 継続（worktree を再開） |
| 「全体を Phase 4.5 から再生成」 | task_checklist.md を全体作り直し |

3. 「計画修正を承認」選択時:
   - `state.json.phase_5_progress.completed_groups` は維持（完了済みグループは再実行しない）
   - `state.json.current_phase` を一時的に `"phase_4_5_mini"` に設定
   - Phase 4.5 を mini モードで実行（詳細は dev-flow-consistency/SKILL.md 参照）
   - mini モード完了後、`state.json.current_phase` を `"phase_4_5"` に戻して Phase 5 を未着手グループから再開

4. 修正履歴を `doc/process/plan_repair_log.md` に記録：

```markdown
# Plan Repair ログ

## 修正 {N} - {日時}
- **エージェント**: {agent}
- **理由**: {reason}
- **選択**: {人間の選択}
- **修正内容**: {suggested_repair}
```

**パース失敗時のフォールバック（フリーテキスト互換）:**

JSON パースに失敗した場合は、テキストに「実装完了」が含まれれば `completed` 扱いとし、「ブロッカー」または「blocked」が含まれれば `blocked` 扱いとします。

---

### STEP D: レビュー

全エージェント完了後、チーム種別に応じてレビューを実行。各レビューは独立したエージェント（model=sonnet）で実行します。

**実行順序：**
- **Infra**: Dev (Infra) レビュー → QA (Infra) レビュー
- **App**: Dev (App) レビュー → QA (App) レビュー
- **Cross**: Dev (Infra) レビュー → QA (Infra) レビュー → Dev (App) レビュー → QA (App) レビュー

#### Dev (Infra) レビュー（Infra / Cross グループ）

Agent を起動（同期実行、`run_in_background=false`, `model="haiku"`, `disallowed_tools=["Edit","Write","NotebookEdit"]`）：

```
あなたは Infra Dev チームの**懐疑的レビュアー（Skeptical Reviewer）**です。
Dev エージェントとは意図的に異なる観点でレビューします。

対象 worktree: {MAIN_DIR}/../worktree-dev-infra-group-N
要件定義書: {REQUIREMENTS_PATHS}
インフラ仕様書: {INFRA_SPEC_PATH}
技術スタック: {tech_stack}

【権限制限】このエージェントは読み取り専用です。Edit/Write/NotebookEdit ツールは使用できません。
git diff や git log などの読み取り系 Bash コマンドは使用可能です。

**レビュー観点（Dev とは異なる独立した観点で確認）:**
- **悪意のあるユーザー視点**: セキュリティホール・権限昇格・インジェクション
- **新人視点**: コードを読んで意図が理解できるか、命名が適切か
- **アーキテクチャ視点**: 拡張性・将来の保守コスト・依存関係

これら3観点のうち最も重大なリスクを持つ1〜2点に絞って指摘してください（全部指摘しない）。

指摘あり → 具体的な修正箇所と理由を報告
指摘なし → 「承認」と報告
```

指摘あり → 指摘が設計レベルの複雑な内容であれば Sonnet に昇格して再レビュー（`model="sonnet"`, 同じ `disallowed_tools` を維持）後、dev-implementer-infra-group-N を再起動して修正（最大5回）

#### Dev (App) レビュー（App / Cross グループ）

同様に App Dev のシニアレビュアーエージェントを起動（`model="haiku"`, `disallowed_tools=["Edit","Write","NotebookEdit"]`、懐疑的レビュアー観点: セキュリティ・新人可読性・アーキテクチャ）。
Haiku で重大指摘があれば Sonnet に昇格して再レビュー。

#### QA (Infra) レビュー（Infra / Cross グループ）

Infra QA のシニアレビュアーエージェントを起動（`model="haiku"`, `disallowed_tools=["Edit","Write","NotebookEdit"]`）。
QA レビュアーは「素朴な質問だけ」する観点を採用: コードの良し悪しではなく、理解できない点・テストの意図が不明な点のみ指摘する。テスト網羅性・独立性・副作用を確認。重大指摘があれば Sonnet に昇格。

#### QA (App) レビュー（App / Cross グループ）

App QA のシニアレビュアーエージェントを起動（`model="haiku"`, `disallowed_tools=["Edit","Write","NotebookEdit"]`、QA 素朴質問観点）。
テスト網羅性・独立性を確認。重大指摘があれば Sonnet に昇格。


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

### STEP G: ドキュメント誤りの集約とマージ待機

**doc_issues の集約（グループ完了後）:**

各エージェントの完了 JSON に `doc_issues` フィールドが含まれている場合、内容を集約してグループ完了時に AskUserQuestion で人間に提示します：

```json
{
  "doc_issues": [
    {
      "doc": "doc/api-spec/auth.md",
      "ref_id": "API-001",
      "issue": "request schema の email フィールドが optional だが要件 REQ-001 では必須",
      "suggested_fix": "required: [email, password] に変更"
    }
  ]
}
```

人間の判断：
- 「ドキュメントを修正する（doc-fix ブランチ）」→ doc-fix フローを実行
- 「実装側で対応する」→ Dev エージェントに修正を依頼
- 「無視する」→ そのまま続行

**doc-fix フロー:**

1. `doc-fix/group-N-{issue-slug}` ブランチを作成
2. 該当ドキュメントを Edit ツールで修正
3. コミット: `docs: ドキュメント誤り修正 - {issue概要}`
4. main ブランチへ PR を作成して人間にマージを依頼
5. マージ後、実装 worktree で `git merge main` して最新ドキュメントを取り込む

**マージ待機:**

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

### state.json とリモート真実の乖離からの復旧

再開時に `completed_groups` に記録されていないグループの worktree 作成が失敗した場合、またはブランチ衝突が発生した場合、GitHub 側のマージ状態を真実のソースとして復旧します：

```bash
# グループ N の全ブランチがマージ済みかを確認
gh pr list --state merged --search "head:dev/infra-group-N" --json number,mergedAt
gh pr list --state merged --search "head:qa/infra-group-N" --json number,mergedAt
# App の場合
gh pr list --state merged --search "head:dev/app-group-N" --json number,mergedAt
gh pr list --state merged --search "head:qa/app-group-N" --json number,mergedAt
```

グループのすべてのブランチが `merged` であれば：

1. `state.json` の `phase_5_progress.completed_groups` に当該グループを追加
2. ローカルブランチが残存していれば削除
3. worktree が残存していれば削除（`--force`）
4. `git fetch origin` で最新状態を取得
5. 次グループの処理を再開

**state.json が破損・消失している場合の全体復旧手順:**

```bash
# 全マージ済みPRを一覧取得してどのグループが完了しているか確認
gh pr list --state merged --json number,headRefName,mergedAt \
  | python3 -c "
import json, sys
prs = json.load(sys.stdin)
for pr in prs:
  branch = pr['headRefName']
  if 'group-' in branch:
    print(f'{branch} -> merged at {pr[\"mergedAt\"]}')
"
```

出力を元に `phase_5_progress.completed_groups` を再構築し、`state.json` を手動または自動で復元する。

