---
name: dev-flow-implementation
description: AI駆動開発フローの implementation ステージ（4/6: 並列実装）。タスクチェックリストの DAG `depends_on` を解決しながらグループを並列実行し、各グループ内で Dev/QA を独立 worktree で並列実装します。Infra/App/Cross の 3 種類のチーム構成に対応し、推論トレース・Plan Repair・独立レビュアー・Implements/Tests コミットフッターを伴います。整合性チェック完了後、または `--from=implementation` 起動時に使用します。
model: haiku
allowed-tools: Read Write Edit Bash Agent SendMessage AskUserQuestion
disable-model-invocation: true
---


# Stage 4/6 implementation: 並列実装（git worktree ワークフロー）

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
| 実装範囲 | チェックリストの全タスク | チェックリストのタスク（差分のみ・既に consistency で絞り込み済み） |
| 既存コードの扱い | 参照のみ（スタイル・規約を合わせる） | 必ず確認し、既存実装がある箇所はスキップ |
| dev/qa implementer モデル | `sonnet` | `sonnet` |

## 事前準備

### STEP 0-a: チェックリストの読み込みと再開判定

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

次に `doc/process/state.json` を Read ツールで読み込み、`implementation_progress` フィールドを確認します。

**`implementation_progress` が存在する場合（前回の中断あり）:**

0. **マージ待ち PR の取り込み**: `pr_numbers` に番号があり `completed_groups` に無いグループについて、各 PR を `gh pr view <N> --json state,url` で確認する
   - グループの全 PR が `MERGED` → そのグループの STEP H（クリーンアップ・`completed_groups` 追加）を実行
   - `OPEN` の PR がある → STEP G の自動マージ試行を再実行。それでも deny された場合はそのグループを「人間マージ待ち」として扱う
   - `CLOSED`（マージされずに閉じられた）→ AskUserQuestion で人間に確認（再作成 / グループをやり直す）
1. `completed_groups` を確認 → 完了済みグループはスキップ対象に記録
2. `active_worktrees` を確認 → 残存 worktree があれば以下でクリーンアップ：
   ```bash
   git worktree remove {MAIN_DIR}/../worktree-dev-group-N --force 2>/dev/null || true
   git worktree remove {MAIN_DIR}/../worktree-qa-group-N --force 2>/dev/null || true
   ```
3. AskUserQuestion で人間に確認：「グループ X から再開します。よろしいですか？」
   - 「再開する」→ 完了済みグループをスキップして処理継続
   - 「最初からやり直す」→ `implementation_progress` を初期化して全グループを再実行

**`implementation_progress` が存在しない場合（初回実行）:**

まず STEP 0-b でベースブランチを確認してから `implementation_progress` を初期化します（base_branch が確定してから書き込むため）。

### STEP 0-b: ベースブランチの確認

```bash
git branch --show-current
```

現在のブランチ名を BASE_BRANCH として記録します。

その後 state.json に `implementation_progress` を初期化して書き込みます：

```json
{
  "implementation_progress": {
    "total_groups": {グループ数},
    "completed_groups": [],
    "active_worktrees": [],
    "base_branch": "{git branch --show-current の結果}",
    "group_types": {
      "group-1": "Infra",
      "group-2": "App",
      "group-3": "Cross"
    },
    "pr_numbers": {}
  }
}
```

`group_types` は STEP 0-a で抽出したチーム種別をすべて記録します。`pr_numbers` は STEP E で PR を作成するたびに `"group-N": [番号, ...]` を追記します

---

## DAGベースのグループ実行ループ

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

**state.json の `implementation_progress` に `depends_on` マップを追加:**

```json
{
  "implementation_progress": {
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

まず、`state.json` の `implementation_progress.group_types["group-N"]` からグループのチーム種別を取得し、実行するエージェントを決定します：

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

グループ N のチーム種別に応じて必要な worktree のみ作成します。共通関数:

```bash
ensure_worktree() {
  local role="$1" team="$2"  # role: dev|qa / team: infra|app
  local path="${MAIN_DIR}/../worktree-${role}-${team}-group-N"
  local branch="${role}/${team}-group-N"
  if git worktree list | grep -q "$(basename "$path")"; then
    echo "${role} (${team}) worktree 既存 → 再利用"
  else
    git worktree add "$path" -b "$branch"
  fi
}
```

| チーム種別 | 作成する worktree |
|---|---|
| **Infra** | `ensure_worktree dev infra` + `ensure_worktree qa infra` |
| **App** | `ensure_worktree dev app` + `ensure_worktree qa app` |
| **Cross** | Infra と App の 4 つすべて |

worktree 作成後、state.json の `implementation_progress.active_worktrees` に作成したブランチ名を追加します：
- Infra: `["dev/infra-group-N", "qa/infra-group-N"]`
- App: `["dev/app-group-N", "qa/app-group-N"]`
- Cross: `["dev/infra-group-N", "qa/infra-group-N", "dev/app-group-N", "qa/app-group-N"]`

---

### STEP B: チーム種別に応じたエージェント起動

Agent Teams（`TeamCreate` / `team_name`）は使用しません。各 implementer は **名前付きサブエージェント**として起動し、結果は最終回答（JSON）で受け取ります。並列起動するものは `run_in_background=true` で同一ターンに起動し、順次起動するものは `run_in_background=false` で 1 つずつ起動します。

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

**エージェント起動前のプロンプト追加注入:**

各エージェント起動前に、以下を順にプロンプトへ注入する。詳細は [reference/agent-prompt-injection.md](reference/agent-prompt-injection.md) を参照。

0. **規約のバージョン照合**: `doc/process/conventions_verified.md` が無い、または `verified_for` のバージョンが `tech_stack.language_version` / `framework_version` と違う場合、[reference/conventions/version-check.md](reference/conventions/version-check.md) の手順で `conventions-verifier` エージェント（`model="sonnet"`、WebFetch 使用）を先に実行して生成する。バージョンが未検出ならマニフェストから検出して `tech_stack` に書き戻す。WebFetch が使えない環境では「未検証」と明記して先へ進む（止めない）
1. **言語・フレームワーク規約**: [reference/conventions/testing.md](reference/conventions/testing.md)（常に）と、`state.json.tech_stack` から [reference/conventions/README.md](reference/conventions/README.md) の選択ルールで `conventions/<language>.md` → `conventions/<framework>.md` → `{project}/doc/conventions.md` を Read し、「書き方」セクションを implementer に、「レビューチェックリスト」を reviewer に、「標準コマンド」を両方に注入する（`{CONVENTIONS}` / `{REVIEW_CHECKLIST}` / `{STANDARD_COMMANDS}` プレースホルダー）。`conventions_verified.md` の「変わった項目」「新しい推奨」は両プレースホルダーの**先頭**に「バージョン照合結果（規約ファイルより優先）」として置く。対応ファイルが無い言語は `_template.md` の観点だけで進め、最終報告で「規約ファイル未整備」と伝える
2. **memory フィードバック**: `~/.claude/projects/$(pwd | sed 's|/|-|g')/memory/` 配下の `feedback_review_*.md` / `feedback_test_failures.md` を読み込んでプロンプト冒頭に追記
3. **ファイルスコープガードレール**: 担当 worktree 配下の作業許可パターンと禁止パターンを明示
4. **Opus 昇格時**: Sonnet 試行履歴と未解決指摘を冒頭に追記

**昇格ラダー（Dev/QA implementer）:**

| 段階 | モデル | 試行 | 昇格条件 |
|---|---|---|---|
| 初回実装 | `sonnet` | 1回 | 完了 → レビューへ |
| 修正実装（Sonnet） | `sonnet` | 最大2回 | レビュー指摘が設計レベルと判定 → Opus 昇格 |
| 修正実装（Opus） | `opus` | 最大3回 | 上限到達 → 人間エスカレーション |

タスク種別による初期モデルの選択：
- CRUD 追加・設定変更など単純タスク → `sonnet` で開始
- 新規アーキテクチャ要素・横断的な変更 → `opus` で開始（state.json の `task_complexity` フィールドで制御。未設定の場合は `sonnet` で開始）

**レビュー指摘・テスト失敗の memory 保存（STEP D/STEP H 後）:**

3 回以上繰り返された指摘や人間によるマージ後修正は、`reference/agent-prompt-injection.md` のフォーマットで memory に保存して次回フローで再注入する。

---

### STEP C: エージェントの完了待機

グループのチーム種別に応じて、各エージェントの完了通知（最終回答の JSON）を待ちます。`sleep` ポーリングはしません：

- **Infra**: `dev-implementer-infra-group-N` + `qa-implementer-infra-group-N` の両方
- **App**: `dev-implementer-app-group-N` + `qa-implementer-app-group-N` の両方
- **Cross**: `dev-implementer-infra-group-N` → `qa-implementer-infra-group-N` → `dev-implementer-app-group-N` → `qa-implementer-app-group-N`（順次）

**JSON パース処理:**

受け取った最終回答を JSON としてパースし、`status` フィールドで以下の通り分岐します：

| status | blocker_type | 対応 |
|---|---|---|
| `"completed"` | — | `result.lint.exit_code` が **0 以外、または欠損**なら「lint / format / 型検査が通っていない」として同じ implementer を `SendMessage` で再開して解消させる（最大 2 回、それでも通らなければ `failed` 扱い）。QA implementer は加えて `result.coverage.changed_functions_below_threshold` が**空でなければ**「未到達分岐の TC をテスト定義書に追加して実装する」よう再開させる（最大 2 回。テストを減らす方向の修正は却下）。両方通ったら `result.commits` をログに記録して次の処理へ進む |
| `"blocked"` | `"plan_repair_needed"` | **Plan Repair フローへ移行**（下記参照） |
| `"blocked"` | その他 | AskUserQuestion で人間に判断を仰ぐ |
| `"failed"` | — | AskUserQuestion で人間に報告し指示を仰ぐ |

**Plan Repair フロー（`blocker_type: "plan_repair_needed"` 受信時）:**

詳細手順は [reference/plan-repair.md](reference/plan-repair.md) を参照。要点：

- 発動上限 3 回。超過時は `requirement_ambiguity` として人間エスカレーション
- AskUserQuestion で「承認 / 却下 / 全体再生成」の3択を提示
- 承認時は `state.json.next_stage` を `"plan_repair"` に切替えて終了。オーケストレーターが consistency を mini モードで実行し、完了後 implementation を未着手グループから再開
- 修正履歴は `doc/process/plan_repair_log.md` に追記

JSON パース失敗時のフォールバックは reference 参照。

---

### STEP D: レビュー

全エージェント完了後、チーム種別に応じてレビューを実行。各レビューは独立したエージェント（`model=opus`）で実行します。レビュアーは設計判断・セキュリティ判断の質を最重要視するため、昇格ラダーを設けず最初から Opus を使用します。

**実行順序：**
- **Infra**: Dev (Infra) レビュー → QA (Infra) レビュー
- **App**: Dev (App) レビュー → QA (App) レビュー
- **Cross**: Dev (Infra) レビュー → QA (Infra) レビュー → Dev (App) レビュー → QA (App) レビュー

#### Dev (Infra) レビュー（Infra / Cross グループ）

Agent を起動（同期実行、`run_in_background=false`, `model="opus"`）。現行の Agent ツールにはツール制限パラメータが無いため、プロンプト冒頭に「**ファイルの編集・作成は禁止。Read / Grep / Bash（読み取り系）のみで確認し、指摘は最終回答で返す**」を必ず含める：

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

**規約チェックリスト（照合必須）:**
{REVIEW_CHECKLIST}
（言語・フレームワーク・プロジェクト規約のルール ID・重大度・確認方法。「確認方法」の grep は実際に実行して確認する）

**テストへの要求（Dev レビューでも見る）:** この実装で増えた・変わった `if` / `switch` / 早期 return / `catch` を列挙し、それぞれに対応する TC がテスト定義書と QA worktree のテストにあるか確認する（`test/branch-coverage`）。無ければ `changes_requested` にして `fix` に「TC-NNN を追加: {分岐の条件}」と書く。QA implementer に回る

**出力（最終回答。SendMessage は使わない）:**

blocker / major は**見つけたものをすべて**挙げる。minor は最大 3 件まで（記録用。修正は求めない）。上の 3 観点で見つけた規約外の問題も、該当ルールが無ければ `rule: "review/<短い名前>"` で報告する。

```json
{
  "reviewer": "dev-infra-group-N",
  "status": "approved | changes_requested",
  "findings": [
    {"severity": "blocker", "rule": "go/sql-injection", "file": "internal/repo/user.go", "line": 42, "problem": "WHERE 句を Sprintf で組み立てている", "fix": "プレースホルダ $1 と引数渡しに変える"},
    {"severity": "minor", "rule": "go/naming", "file": "internal/repo/user.go", "line": 10, "problem": "レシーバ名が r と repo で混在", "fix": "r に統一"}
  ],
  "checked_rules": ["go/sql-injection", "go/errors-wrap", "..."]
}
```

`status` は blocker または major が 1 件でもあれば `changes_requested`、それ以外は `approved`。
```

`changes_requested` → `findings` のうち blocker / major を dev-implementer-infra-group-N に `SendMessage` で渡して修正（最大5回）。minor は memory 蓄積用に記録するだけで修正ループに回さない。レビュアーは初回から Opus を使用するため、追加昇格は行わない。同じ `rule` が 3 回以上出たら [reference/agent-prompt-injection.md](reference/agent-prompt-injection.md) の手順で memory に保存する。

#### Dev (App) レビュー（App / Cross グループ）

同様に App Dev のシニアレビュアーエージェントを起動（`model="opus"`、編集禁止をプロンプトに明記、懐疑的レビュアー観点: セキュリティ・新人可読性・アーキテクチャ、`{REVIEW_CHECKLIST}` の照合、同じ JSON 出力）。
`changes_requested` → blocker / major を dev-implementer-app-group-N に渡して修正（最大5回）。

#### QA (Infra) レビュー（Infra / Cross グループ）

Infra QA のシニアレビュアーエージェントを起動（`model="opus"`、編集禁止をプロンプトに明記）。
QA レビュアーは「素朴な質問だけ」する観点を採用: コードの良し悪しではなく、理解できない点・テストの意図が不明な点のみ指摘する。`{REVIEW_CHECKLIST}` のうち `test/*`（[conventions/testing.md](reference/conventions/testing.md)）と各言語のテスト関連ルール（`*/table-driven` `*/parametrize` `*/test-*` 等）を照合する。特に `test/no-delete` / `test/no-skip` / `test/expected-from-impl` は blocker。`git diff` で削除行を確認し、`result.coverage` の未到達分岐と実装の分岐を突き合わせる。出力は Dev レビューと同じ JSON。`changes_requested` → qa-implementer-infra-group-N に渡して修正（最大5回）。

#### QA (App) レビュー（App / Cross グループ）

App QA のシニアレビュアーエージェントを起動（`model="opus"`、編集禁止をプロンプトに明記、QA 素朴質問観点）。
`{REVIEW_CHECKLIST}` の `test/*` と言語のテスト関連ルールを照合（Infra QA と同じ基準）。出力は同じ JSON。`changes_requested` → qa-implementer-app-group-N に渡して修正（最大5回）。


---

### STEP E: PR作成

レビュー承認後、チーム種別に応じてブランチをpushしてPRを作成：

- **Infra**: `dev/infra-group-N`, `qa/infra-group-N` → 2PR作成、label=`infra`
- **App**: `dev/app-group-N`, `qa/app-group-N` → 2PR作成、label=`app`
- **Cross**: 4ブランチすべて → 4PR作成、Infraブランチには`infra,cross`、Appブランチには`app,cross`

PRタイトル例: 
- `feat(infra): グループ N Infra Dev タスク実装`
- `test(infra): グループ N Infra QA タスク実装`

PR のベースブランチは `implementation_progress.base_branch`（`--base` で明示する）。作成した PR 番号はすべて `state.json` の `implementation_progress.pr_numbers["group-N"]` に**配列**で記録する：

```bash
gh pr create --base "$BASE_BRANCH" --head dev/infra-group-N --title "..." --body "..." --label infra
# → 出力 URL の末尾番号を pr_numbers["group-N"] に append
```

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

**自動マージ試行（非ブロッキング）:**

マージを**待たない**。まず hook の有無を確認する：

```bash
jq -e '[.. | strings | select(test("pr-merge-guard"))] | length > 0' ~/.claude/settings.json >/dev/null 2>&1 && echo enabled || echo disabled
```

- `disabled` → `gh pr merge` を発行せず、PR URL を人間に提示して stage-implementation-agent を終了する（マージ後に `/dev-flow` で再入）
- `enabled` → グループの各 PR に対して 1 コマンドずつ `gh pr merge <N> --merge --delete-branch` を実行する。hook `pr-merge-guard.sh` が自動マージ条件（ベースが `feature/*` かつ `base_branch` と一致・CI 全通過・コンフリクトなし・DB 破壊的変更なし）を検証し、満たさなければ deny される

結果の扱い：

| 結果 | 動作 |
|---|---|
| グループの全 PR がマージされた | STEP H へ |
| 一部または全部が deny された | deny 理由を記録し、そのグループを「人間マージ待ち」とする。依存の無い他グループがあれば続行、無ければ人間に「以下の PR は自動マージ条件を満たしません。レビュー・マージ後に `/dev-flow` を実行してください」と PR URL・理由を提示して**終了** |
| CI が `PENDING` で deny された | 待たずに上記と同じ扱い（次回 `/dev-flow` の再開処理が再試行する） |

deny を回避する目的で `--admin` / `--auto` / `--squash` を試したり、条件を満たすようにファイルを削って再 push したりしてはならない。

---

### STEP H: マージ後クリーンアップ

グループの全 PR が `MERGED` であることを `gh pr view <N> --json state` で確認した後（自動マージ直後、または再開処理での取り込み時）：

1. ローカル・リモートブランチを削除：
   - Infra: `dev/infra-group-N`, `qa/infra-group-N`
   - App: `dev/app-group-N`, `qa/app-group-N`
   - Cross: 上記4ブランチすべて
2. `doc/process/task_checklist.md` のグループNタスクを `[x]` に更新
3. `doc/process/state.json` の `implementation_progress` を更新（`completed_groups`に追加、`active_worktrees`をリセット）
4. 上記2ファイルを1コミットで記録

---

## 全グループ完了後

すべてのグループ完了後：

1. `doc/process/state.json` を更新：
   - `next_stage` を `"test"` に変更
   - `implementation_progress` を削除
   - **`mode == "incremental"` の場合のみ**：`baseline_commit` を `git rev-parse HEAD`（ベースブランチに全 PR がマージされた後の最新コミット）で上書き。これにより、次回 `incremental` 実行時の差分基点が今回マージ完了時点に進む
2. 人間に「implementation 完了。次は `/dev-flow` を実行して test（テスト実行）に進んでください」と通知

`baseline_commit` 更新の責任分担詳細は `~/.claude/skills/dev-flow/reference/state-schema.md` の「baseline_commit のライフサイクル」を参照。

---

## エラーハンドリング

| 状況 | 対応 |
|---|---|
| worktree作成失敗 | 既存worktreeをクリーンアップ後に再試行 |
| push失敗 | 人間に報告して解消後に再push |
| lint エラー解消不可 | 人間に報告 |
| ブロッカー発生 | エージェント停止して人間に判断を仰ぐ |

### state.json とリモート真実の乖離からの復旧

worktree 作成失敗・ブランチ衝突・state.json 破損時は GitHub 側のマージ状態を真実として復旧する。手順は [reference/recovery.md](reference/recovery.md) を Read すること。
