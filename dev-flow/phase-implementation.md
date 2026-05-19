---
skill: dev-flow:phase-implementation
description: 並列実装フェーズ（Phase 5）- git worktree でグループ並列実装 → 順次マージ
model: haiku
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

## 事前準備

### 5-pre-a: チェックリストの読み込み

`doc/process/task_checklist.md` を Read ツールで読み込み、「並列実行グループ」セクションを解析します。

- グループ数を確認する（グループ 1、グループ 2、...）
- 各グループの Dev タスク・QA タスクを一覧化する

### 5-pre-b: ベースブランチの確認

```bash
git branch --show-current
```

現在のブランチ名を BASE_BRANCH として記録します。

---

## Phase 5: グループ単位のループ

グループ 1 から順に以下を繰り返します。**グループ間は直列**（前グループのマージ完了後に次グループを開始）、**グループ内は並列**（Dev と QA を同時に worktree で実行）。

---

### STEP A: worktree の作成（グループ開始時）

グループ N に対して2本の worktree ブランチを作成します。

```bash
# Dev チーム用 worktree
git worktree add ../worktree-dev-group-N -b dev/group-N

# QA チーム用 worktree
git worktree add ../worktree-qa-group-N -b qa/group-N
```

- Dev worktree パス: `../worktree-dev-group-N`
- QA worktree パス: `../worktree-qa-group-N`
- ベースは現在の BASE_BRANCH の HEAD

---

### STEP B: Dev チームと QA チームを並列起動

以下の2エージェントを **同時に** 起動します（どちらも `run_in_background=true`）。

---

#### dev-implementer-group-N

モデル: `sonnet`

---

あなたは Dev チームの実装担当です。**グループ N** の実装タスクを完成させてください。

**作業ディレクトリ: `../worktree-dev-group-N`（このパスで作業すること）**

まず以下のドキュメントを Read ツールで読み込んでください（トークン節約のため、スペックキャッシュを優先すること）：
- スペックキャッシュ: `{メインディレクトリ}/docs/internal/spec_cache.md`
- テスト定義書: `{メインディレクトリ}/{TEST_SPEC_PATH}`
- タスクチェックリスト（グループ N の Dev タスクのみ対象）: `{メインディレクトリ}/doc/process/task_checklist.md`
- モック HTML（IS_GUI=true の場合）: `{メインディレクトリ}/{MOCK_PATH}`

詳細が必要な場合のみ要件定義書を参照すること: {メインディレクトリ}/{REQUIREMENTS_PATHS}

技術スタック: `{tech_stack}`

### グループ N の Dev タスク一覧

{チェックリストから抽出したグループ N の Dev タスク一覧}

### 実装ループ

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

**5. 全タスク完了 → メインオーケストレーターに完了を報告する**

---

#### qa-implementer-group-N

モデル: `sonnet`

---

あなたは QA チームの実装担当です。**グループ N** の QA タスクを完成させてください。

**作業ディレクトリ: `../worktree-qa-group-N`（このパスで作業すること）**

まず以下のドキュメントを Read ツールで読み込んでください（トークン節約のため、スペックキャッシュを優先すること）：
- スペックキャッシュ: `{メインディレクトリ}/docs/internal/spec_cache.md`
- テスト定義書: `{メインディレクトリ}/{TEST_SPEC_PATH}`
- タスクチェックリスト（グループ N の QA タスクのみ対象）: `{メインディレクトリ}/doc/process/task_checklist.md`

詳細が必要な場合のみ要件定義書を参照すること: {メインディレクトリ}/{REQUIREMENTS_PATHS}

技術スタック: `{tech_stack}`

### グループ N の QA タスク一覧

{チェックリストから抽出したグループ N の QA タスク一覧}

### 実装ループ

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

**5. 全タスク完了 → メインオーケストレーターに完了を報告する**

---

### STEP C: 両エージェントの完了待機

dev-implementer-group-N と qa-implementer-group-N の両方の完了通知を待ちます。片方がブロッカーを報告した場合は、AskUserQuestion で人間に状況を伝えて判断を仰ぎます。

---

### STEP D: レビュー（Dev → QA の順）

両エージェントの完了後、それぞれの成果物をレビューします。

#### Dev レビュー

以下のプロンプトで Agent を起動（同期実行、`run_in_background=false`, `model="sonnet"`）：

---

あなたは Dev チームのシニアエンジニア（レビュアー）です。

対象 worktree: `../worktree-dev-group-N`
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

指摘があった場合: dev-implementer-group-N を再起動して修正させ、完了後に再レビューします（承認まで繰り返す）。

#### QA レビュー

以下のプロンプトで Agent を起動（同期実行、`run_in_background=false`, `model="sonnet"`）：

---

あなたは QA チームのシニアエンジニア（レビュアー）です。

対象 worktree: `../worktree-qa-group-N`
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

指摘があった場合: qa-implementer-group-N を再起動して修正させ、完了後に再レビューします（承認まで繰り返す）。

---

### STEP E: PR の作成

両レビュー承認後、ブランチを push して PR を作成します。

```bash
# ブランチを push
git -C ../worktree-dev-group-N push origin dev/group-N
git -C ../worktree-qa-group-N push origin qa/group-N

# Dev PR を作成
gh pr create \
  --head dev/group-N \
  --base {BASE_BRANCH} \
  --title "feat: グループ N Dev タスク実装" \
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
git worktree remove ../worktree-dev-group-N --force
git worktree remove ../worktree-qa-group-N --force
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
- 「PR に修正が必要」→ 指摘内容を受けて該当 worktree を再作成し、修正・再 push・PR 更新後に再度待機

---

### STEP H: マージ後のクリーンアップ & チェックリスト更新

マージ確認後、以下を実行します：

```bash
# ローカルブランチを削除
git branch -d dev/group-N
git branch -d qa/group-N

# リモートブランチを削除（gh でマージ済みの場合は自動削除されていることが多いが念のため）
git push origin --delete dev/group-N 2>/dev/null || true
git push origin --delete qa/group-N 2>/dev/null || true
```

次に `doc/process/task_checklist.md` のグループ N の全タスク行を `[x]` に更新します。

---

## 全グループ完了後

すべてのグループの STEP H（マージ確認 & クリーンアップ）が完了したら、以下を実行：

1. `doc/process/state.json` を更新（current_phase を `"phase_5"` に）
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
