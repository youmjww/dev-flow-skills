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
    "base_branch": "{git branch --show-current の結果}"
  }
}
```

---

## Phase 5: グループ単位のループ

グループ 1 から順に以下を繰り返します。**グループ間は直列**（前グループのマージ完了後に次グループを開始）、**グループ内は並列**（Dev と QA を同時に worktree で実行）。

---

### STEP A: worktree の作成（グループ開始時）

`completed_groups` に含まれるグループは **スキップ** して次のグループへ進みます。

まず作業ディレクトリの絶対パスを確認します：

```bash
MAIN_DIR=$(pwd)
echo "メインディレクトリ: $MAIN_DIR"
```

グループ N に対して2本の worktree ブランチを冪等に作成します：

```bash
# Dev チーム用 worktree（既存チェック → あれば再利用、なければ作成）
if git worktree list | grep -q "worktree-dev-group-N"; then
  echo "Dev worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/{MAIN_DIR}/../worktree-dev-group-N" -b dev/group-N
fi

# QA チーム用 worktree（既存チェック → あれば再利用、なければ作成）
if git worktree list | grep -q "worktree-qa-group-N"; then
  echo "QA worktree 既存 → 再利用"
else
  git worktree add "${MAIN_DIR}/{MAIN_DIR}/../worktree-qa-group-N" -b qa/group-N
fi
```

- Dev worktree パス: `{MAIN_DIR}/{MAIN_DIR}/../worktree-dev-group-N`（絶対パス）
- QA worktree パス: `{MAIN_DIR}/{MAIN_DIR}/../worktree-qa-group-N`（絶対パス）
- ベースは現在の BASE_BRANCH の HEAD

worktree 作成後、state.json の `phase_5_progress.active_worktrees` に `["dev/group-N", "qa/group-N"]` を追加します。

---

### STEP B: Dev チームと QA チームを並列起動

以下の2エージェントを **同時に** 起動します（どちらも `run_in_background=true`）。

---

#### dev-implementer-group-N

モデル: `sonnet`

---

あなたは Dev チームの実装担当です。**グループ N** の実装タスクを完成させてください。

**作業ディレクトリ: `{MAIN_DIR}/../worktree-dev-group-N`（このパスで作業すること）**

開発モード: `{MODE}`
baseline_commit: `{BASELINE_COMMIT}`

まず以下のドキュメントを Read ツールで読み込んでください（トークン節約のため、スペックキャッシュを優先すること）：
- スペックキャッシュ: `{メインディレクトリ}/doc/internal/spec_cache.md`
- テスト定義書: `{メインディレクトリ}/{TEST_SPEC_PATH}`
- タスクチェックリスト（グループ N の Dev タスクのみ対象）: `{メインディレクトリ}/doc/process/task_checklist.md`
- モック HTML（IS_GUI=true の場合）: `{メインディレクトリ}/{MOCK_PATH}`

詳細が必要な場合のみ要件定義書を参照すること: {メインディレクトリ}/{REQUIREMENTS_PATHS}

技術スタック: `{tech_stack}`

### グループ N の Dev タスク一覧

{チェックリストから抽出したグループ N の Dev タスク一覧}

### 実装ループ

**0. mode = "incremental" の場合：実装前に既存コードを確認する（必須）**

各タスクの実装を始める前に、関連する既存ファイルを Read ツールで確認してください：
```bash
# 関連ファイルを探す
find {MAIN_DIR} -type f \( -name "*.tf" -o -name "*.py" -o -name "*.ts" -o -name "*.tsx" \) \
  ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/__pycache__/*" \
  | xargs grep -l "{タスクに関するキーワード}" 2>/dev/null | head -5
```

確認した結果：
- **既存実装がある** → そのファイルを Read して内容を把握した上で、差分のみ追加・修正する。既存コードを削除・書き直ししない
- **既存実装がない** → 新規実装する

**1. タスクを1件選んで実装する**
- `{tech_stack.language}` / `{tech_stack.framework}` で実装する
- 既存コードのスタイル・規約に従う
- テスト定義書を参照し、テストから呼び出しやすいインターフェース設計にする

**2. ブロッカーチェック**
- 要件の解釈が複数あり判断できない場合は、実装を中断してメインオーケストレーターに報告する：
  - ブロッカーの内容
  - 判断が必要な選択肢
  - 推奨案（あれば）

**3. lint / format の実行**（worktree ディレクトリ内で実行）
- `{tech_stack.linter}` / `{tech_stack.formatter}` を実行してエラーをすべて解消する

**4. タスク単位コミット**（worktree ディレクトリ内で git commit）
- コミットメッセージ例: `feat: {機能名} を実装`
- **チェックリストの更新はしない**（マージ後にオーケストレーターが行う）

**5. 全タスク完了 → `SendMessage(to: "phase-impl-agent", message: "dev-group-N 実装完了")` で報告する**

---

#### qa-implementer-group-N

モデル: `sonnet`

---

あなたは QA チームの実装担当です。**グループ N** の QA タスクを完成させてください。

**作業ディレクトリ: `{MAIN_DIR}/../worktree-qa-group-N`（このパスで作業すること）**

開発モード: `{MODE}`
baseline_commit: `{BASELINE_COMMIT}`

まず以下のドキュメントを Read ツールで読み込んでください（トークン節約のため、スペックキャッシュを優先すること）：
- スペックキャッシュ: `{メインディレクトリ}/doc/internal/spec_cache.md`
- テスト定義書: `{メインディレクトリ}/{TEST_SPEC_PATH}`
- タスクチェックリスト（グループ N の QA タスクのみ対象）: `{メインディレクトリ}/doc/process/task_checklist.md`

詳細が必要な場合のみ要件定義書を参照すること: {メインディレクトリ}/{REQUIREMENTS_PATHS}

技術スタック: `{tech_stack}`

### グループ N の QA タスク一覧

{チェックリストから抽出したグループ N の QA タスク一覧}

### 実装ループ

**0. mode = "incremental" の場合：実装前に既存テストを確認する（必須）**

各タスクの実装を始める前に、関連する既存テストファイルを Read ツールで確認してください：
- 既存テストがある → 重複するテストは追加しない。テストが不足している箇所のみ追記する
- 既存テストがない → 新規テストファイルを作成する

**1. タスクを1件選んでテストコードを生成する**
- テスト定義書の該当ケースを `{tech_stack.test_framework}` で実装する
- テスト名は日本語で記述（「正常系: 〜」「異常系: 〜」形式）
- プロダクションコードが未実装の場合はインターフェースを要件から推定する

**2. ブロッカーチェック**
- テスト定義書の内容が実装と根本的に矛盾すると判断した場合は、実装を中断してメインオーケストレーターに報告する

**3. lint / format の実行**（worktree ディレクトリ内で実行）
- `{tech_stack.linter}` / `{tech_stack.formatter}` を実行してエラーをすべて解消する

**4. タスク単位コミット**（worktree ディレクトリ内で git commit）
- コミットメッセージ例: `test: {テスト名} を実装`
- **チェックリストの更新はしない**（マージ後にオーケストレーターが行う）

**5. 全タスク完了 → `SendMessage(to: "phase-impl-agent", message: "qa-group-N 実装完了")` で報告する**

---

### STEP C: 両エージェントの完了待機

`dev-group-N 実装完了` と `qa-group-N 実装完了` の両 SendMessage を受信するまで待ちます。片方がブロッカーを報告した場合は、AskUserQuestion で人間に状況を伝えて判断を仰ぎます。

---

### STEP D: レビュー（Dev → QA の順）

両エージェントの完了後、それぞれの成果物をレビューします。

#### Dev レビュー

以下のプロンプトで Agent を起動（同期実行、`run_in_background=false`, `model="sonnet"`）：

---

あなたは Dev チームのシニアエンジニア（レビュアー）です。

対象 worktree: `{MAIN_DIR}/../worktree-dev-group-N`
要件定義書（全ファイルを順に読み込んでください）: {REQUIREMENTS_PATHS}
技術スタック: `{tech_stack}`

**重要: ファイルの読み取りのみ行い、いかなるファイルも変更しないこと。**

worktree 内の実装ファイルを Read ツールで読み込み、以下の観点でレビューしてください：
- **要件充足**: 要件定義書の対象機能が実装されているか
- **セキュリティ**: `{tech_stack.language}` 特有の脆弱性パターン
- **パフォーマンス**: N+1・不要なアロケーション・ブロッキング処理
- **可読性・冗長性**: ロジックの重複・命名の一貫性

指摘あり → 具体的な修正箇所と理由を箇条書きで報告する
指摘なし → 「承認」と報告する

---

指摘があった場合: dev-implementer-group-N を再起動して修正させ、完了後に再レビューします（最大5回。上限に達した場合は AskUserQuestion で人間に報告して指示を仰ぐ）。

#### QA レビュー

以下のプロンプトで Agent を起動（同期実行、`run_in_background=false`, `model="sonnet"`）：

---

あなたは QA チームのシニアエンジニア（レビュアー）です。

対象 worktree: `{MAIN_DIR}/../worktree-qa-group-N`
テスト定義書: `{TEST_SPEC_PATH}`
技術スタック: `{tech_stack}`

**重要: ファイルの読み取りのみ行い、いかなるファイルも変更しないこと。**

worktree 内のテストファイルを Read ツールで読み込み、以下の観点でレビューしてください：
- テスト定義書の全ケースが網羅されているか
- `{tech_stack.language}` のテストイディオムに従っているか
- テストの独立性・再現性が担保されているか
- モック・スタブの使い方が適切か

指摘あり → 具体的な修正箇所と理由を箇条書きで報告する
指摘なし → 「承認」と報告する

---

指摘があった場合: qa-implementer-group-N を再起動して修正させ、完了後に再レビューします（最大5回。上限に達した場合は AskUserQuestion で人間に報告して指示を仰ぐ）。

---

### STEP E: PR の作成

両レビュー承認後、ブランチを push して PR を作成します。**チェックリストの更新はマージ確認後（STEP H）に行います。**

```bash
# ブランチを push
git -C {MAIN_DIR}/../worktree-dev-group-N push origin dev/group-N
git -C {MAIN_DIR}/../worktree-qa-group-N push origin qa/group-N

# Dev PR を作成
gh pr create \
  --head dev/group-N \
  --base {BASE_BRANCH} \
  --title "feat: グループ N Dev タスク実装" \
  --label "claude" \
  --assignee "@me" \
  --body "$(cat <<'EOF'
## 概要
チェックリスト グループ N の Dev タスクを実装しました。

## 実装タスク
{グループ N の Dev タスク一覧を箇条書きで記載}

## レビュー観点
- 要件定義書との整合性
- セキュリティ・パフォーマンス
- コードスタイル・命名規則
EOF
)"

# QA PR を作成
gh pr create \
  --head qa/group-N \
  --base {BASE_BRANCH} \
  --title "test: グループ N QA タスク実装" \
  --label "claude" \
  --assignee "@me" \
  --body "$(cat <<'EOF'
## 概要
チェックリスト グループ N の QA タスクを実装しました。

## 実装タスク
{グループ N の QA タスク一覧を箇条書きで記載}

## レビュー観点
- テスト定義書との網羅性
- テストの独立性・再現性
- モック・スタブの適切性
EOF
)"
```

---

### STEP F: worktree のクリーンアップ

PR 作成後、worktree ディレクトリを削除します（ブランチは PR がマージされるまで保持）。

```bash
git worktree remove {MAIN_DIR}/../worktree-dev-group-N --force
git worktree remove {MAIN_DIR}/../worktree-qa-group-N --force
```

---

### STEP G: 人間レビュー・マージ待機

AskUserQuestion で人間に PR URL を提示し、マージ完了を確認します：

```
グループ N の PR を作成しました。レビュー・マージをお願いします。

- Dev PR: {Dev PR の URL}
- QA PR:  {QA PR の URL}

マージ完了後、次のグループへ進みます。
```

選択肢:
- 「マージしました。次のグループへ進む」→ STEP H へ
- 「PR に修正が必要」→ 以下の手順で worktree を再作成して修正・再 push・PR 更新後に再度待機：
  ```bash
  # worktree は削除済みのためリモートブランチから再作成
  git worktree add {MAIN_DIR}/../worktree-dev-group-N --track origin/dev/group-N
  git worktree add {MAIN_DIR}/../worktree-qa-group-N --track origin/qa/group-N
  ```
  修正後は `git push origin dev/group-N` で既存 PR に反映（PR 再作成は不要）。完了後に STEP G に戻る。

---

### STEP H: マージ後のクリーンアップ

マージ確認後、以下を順に実行します：

```bash
# ローカルブランチを削除
git branch -d dev/group-N
git branch -d qa/group-N

# リモートブランチを削除（gh でマージ済みの場合は自動削除されていることが多いが念のため）
git push origin --delete dev/group-N 2>/dev/null || true
git push origin --delete qa/group-N 2>/dev/null || true
```

ブランチ削除後、以下を1コミットで原子的に記録します：

1. `doc/process/task_checklist.md` のグループ N の全タスク行を `[ ]` → `[x]` に更新
2. `doc/process/state.json` の `phase_5_progress` を更新：
   - `completed_groups` に `"group-N"` を追加
   - `active_worktrees` を `[]` にリセット

```bash
# checklist と state.json を同時にコミット
git add doc/process/task_checklist.md doc/process/state.json
git commit -m "chore: グループN 完了（checklist・state 更新）"
```

コミットが失敗した場合（pre-commit hook エラー等）：
1. `git status` で状態を確認する
2. フックエラーであれば原因を修正して再度コミットする
3. 解消できない場合は AskUserQuestion で人間に報告して指示を仰ぐ（`git restore --staged` は使わない）

これで「マージ済み = チェック済み = state 記録済み」の整合が保たれます。

---

## 全グループ完了後

すべてのグループの STEP H（マージ確認 & クリーンアップ）が完了したら、以下を実行：

1. `doc/process/state.json` を更新：
   - `current_phase` を `"phase_5"` に変更
   - `phase_5_progress` フィールドを削除（完了済みのため不要）
2. 人間に「Phase 5 完了。次は `/dev-flow` を実行して Phase 6 に進んでください」と通知

---

## エラーハンドリング

| 状況 | 対応 |
|---|---|
| worktree 作成失敗（パス重複等） | 既存 worktree を `git worktree list` で確認してクリーンアップ後に再試行 |
| push 失敗（認証・権限等） | AskUserQuestion で人間に報告し、解消後に再 push |
| PR に修正指摘（STEP G） | worktree を再作成して修正・再 push・PR 更新後に再度 STEP G へ |
| lint エラーが解消できない | メインオーケストレーターに報告して人間に判断を仰ぐ |
| ブロッカー発生 | 該当エージェントを停止し、AskUserQuestion で人間に判断を仰いだ後に再起動 |
