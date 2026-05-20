---
name: dev-flow
description: AI駆動開発フローのメインオーケストレーター。要件定義→ドキュメント生成→整合性チェック→並列実装→テスト→準拠チェックの全フェーズをサブエージェント経由で順次実行します。新機能を要件定義から実装まで一気通貫で自動化したい時、または `doc/process/state.json` から既存フローを継続したい時に使用します。
model: haiku
# WebSearch / WebFetch はサブエージェント（spec・compliance フェーズ）が技術仕様・ライブラリドキュメントを参照するために必要
allowed-tools: Read Write Edit Bash Agent TaskCreate TaskUpdate AskUserQuestion WebSearch WebFetch
---

# 開発フローオーケストレーター

あなたは開発フローの**メインオーケストレーター**です。状態ファイルを管理し、各フェーズのスキルをサブエージェント経由で順次実行してフローを進めます。

---

## 状態管理

状態ファイル: `doc/process/state.json`

主要フィールド: `current_phase` / `mode`（full or incremental）/ `baseline_commit` / `tech_stack` / `phase_5_progress`

スキーマ詳細・PR マージ待機ロジック・harness メタデータは必要時に Read すること:
`~/.claude/skills/dev-flow/reference/state-schema.md`

---

## フロー実行

### STEP 1: 引数の解析

`{{ARGS}}` を解析：

- **TASK**: `--` で始まらない部分
- **FROM**: `--from=` の値（指定時は state.json の current_phase を上書き）
- **DRY_RUN**: ARGS に `"--dry-run"` が含まれる場合は `true`。サブエージェントを起動せずフロー構成を検証して終了する

`--from` 対応表:

| 値 | 開始フェーズ | state.json 要否 |
|---|---|---|
| `requirements` または 未指定かつ state.json なし | Phase 1 | 不要 |
| `spec` | Phase 3 | 必要 |
| `parallel` | Phase 5 | 必要 |
| `test` | Phase 6 | 必要 |
| `sync` | Phase 7 | 必要 |

### STEP 1.2: 下流スキルファイルの事前検証

STEP 1 直後に必ず実行（`--dry-run` の有無に関わらず）。欠損を早期検知する：

```bash
for f in \
  ~/.claude/skills/dev-flow-requirements/SKILL.md \
  ~/.claude/skills/dev-flow-spec/SKILL.md \
  ~/.claude/skills/dev-flow-consistency/SKILL.md \
  ~/.claude/skills/dev-flow-implementation/SKILL.md \
  ~/.claude/skills/dev-flow-test/SKILL.md \
  ~/.claude/skills/dev-flow-compliance/SKILL.md; do
  [ -f "$f" ] || echo "MISSING: $f"
done
```

判定と後続動作：

| 検証結果 | DRY_RUN=false | DRY_RUN=true |
|---|---|---|
| `MISSING:` 行が1件以上 | AskUserQuestion で人間に報告して中断 | 下記 dry-run 出力で欠損行を `✗` で示してから終了 |
| すべて存在 | STEP 1.5 へ進む | 下記 dry-run 出力で全行 `✓` を示してから終了（STEP 1.5 以降はスキップ） |

**`--dry-run` 時の出力例:**

```
[dry-run] 実行計画:
  Phase 1-2: phase-requirements-agent (opus)  ← 下流スキル: 存在 ✓
  Phase 3-4: phase-spec-agent (haiku)          ← 下流スキル: 欠損 ✗  ~/.claude/skills/dev-flow-spec/SKILL.md が見つかりません
  ...
✅ 全スキルファイル確認完了 / ❌ 欠損スキルあり。setup.sh を実行してください。
```

### STEP 1.5: 開発モードの判定（state.json が存在しない場合のみ）

**1. 既存実装の確認:**

テストファイルのみのリポジトリを「既存実装あり」と誤判定しないよう、テスト系ファイルを除外してから本体実装をカウントする：

```bash
git log --oneline -1 2>/dev/null
git ls-files \
  | grep -vE '(^|/)(tests?|spec|__tests__)/' \
  | grep -vE '\.(test|spec)\.(ts|tsx|js|jsx|py|rb)$' \
  | grep -vE '_test\.(go|py|rb)$' \
  | grep -cE '\.(go|py|ts|tsx|js|jsx|rb|java|rs|kt|swift|c|cpp|cs)$' 2>/dev/null || echo 0
```

出力が `1` 以上 → 実装コードあり。`0` → `"full"` モード確定。

**2. 既存コミットと実装コードが両方存在する場合:** AskUserQuestion で確認：

| 選択肢 | mode | baseline_commit |
|---|---|---|
| 新規開発（ゼロから全機能実装） | `"full"` | `null` |
| 要件追加（既存実装への差分のみ追加） | `"incremental"` | `git rev-parse HEAD` |

### STEP 2: 状態ファイルの読み込み

`doc/process/state.json` が存在する場合、Read で `current_phase` を確認。`--from` 引数が指定されている場合はそちらを優先。

### STEP 3: タスクチェックリストの確認・表示

`doc/process/task_checklist.md` が存在する場合、Read してフェーズ進捗を人間に表示。

### STEP 3.5: エージェント階層安全装置の確認

**1. 階層深さ上限チェック:** `state.json.agent_hierarchy.current_depth >= max_depth(4)` → AskUserQuestion でエスカレーション。それ以外 → 起動時に `+1`、完了時に `-1`。

**2. 無限ループ検出:** 同じ `(phase, agent_name)` の組み合わせが `harness.phase_history` に5回以上あれば AskUserQuestion で確認。

**3. タイムアウト目安:** haiku=5分 / sonnet=15分 / opus=30分。超過時は AskUserQuestion で人間に確認。

### STEP 4: タスクを作成してサブエージェントを起動

**フェーズ対応表:**

| current_phase | タスク名 | エージェント name | モデル | スキルファイル |
|---|---|---|---|---|
| なし（初回） | Phase 1-2: 要件定義 | `phase-requirements-agent` | opus | `dev-flow-requirements/SKILL.md` |
| phase_2 | Phase 3-4: ドキュメント生成 | `phase-spec-agent` | haiku | `dev-flow-spec/SKILL.md` |
| phase_4 | Phase 4.5: 整合性チェック | `phase-consistency-agent` | haiku | `dev-flow-consistency/SKILL.md` |
| phase_4_5 | Phase 5: 並列実装 | `phase-impl-agent` | haiku | `dev-flow-implementation/SKILL.md` |
| phase_4_5_mini | Phase 4.5（mini）: 計画修正 | `phase-consistency-mini-agent` | haiku | `dev-flow-consistency/SKILL.md` |
| phase_5 | Phase 6: テスト実行 | `phase-test-agent` | haiku | `dev-flow-test/SKILL.md` |
| phase_6 | Phase 7-8: 準拠チェック・完了 | `phase-compliance-agent` | opus | `dev-flow-compliance/SKILL.md` |

スキルファイルのパスはすべて `~/.claude/skills/` 配下。

**`phase_4_5_mini` 特別処理:**

Plan Repair によって設定される一時フェーズ。発動シーケンスは下記：

| # | アクター | 動作 |
|---|---|---|
| 1 | `phase-impl-agent` | Phase 5 中にグループから `status: "blocked"` / `blocker_type: "plan_repair_needed"` を受信 |
| 2 | `phase-impl-agent` | AskUserQuestion で「承認 / 却下 / 全体再生成」を提示。承認時に `state.json.current_phase` を `"phase_4_5_mini"` に書き換えて終了 |
| 3 | `dev-flow` オーケストレーター | 次イテレーションで `current_phase = "phase_4_5_mini"` を検出し `phase-consistency-mini-agent`（mini モード）を起動 |
| 4 | `phase-consistency-mini-agent` | 未着手グループのみチェックリストを再生成し、完了後 `current_phase` を `"phase_4_5"` に書き戻して終了 |
| 5 | `dev-flow` オーケストレーター | `current_phase = "phase_4_5"` を検出して Phase 5 を未着手グループから再開 |

Plan Repair の発動上限は **3 回**。超過時は `requirement_ambiguity` として人間エスカレーション。詳細は `~/.claude/skills/dev-flow-implementation/SKILL.md` の「Plan Repair フロー」および `dev-flow-implementation/reference/plan-repair.md` を参照。

**タスク作成:**

```
TaskCreate(name: "{タスク名}", description: "dev-flow: {タスク名} を実行中")
TaskUpdate(id: "{task_id}", status: "in_progress")
```

**サブエージェント起動:** オーケストレーターがスキルファイルを事前 Read し、フェーズに必要なセクションのみ抽出してプロンプトに直接埋め込む（トークン削減）。2000トークン以下なら全文渡し可。

| フェーズ | 渡すセクション | 省略するセクション |
|---|---|---|
| Phase 1-2 | 要件定義手順・出力フォーマット・AskUserQuestion 指示 | フロー全体像・他フェーズ手順 |
| Phase 3-4 | ドキュメント生成手順・各仕様書フォーマット | フロー全体像・実装手順 |
| Phase 4.5 | 整合性チェック手順・差分検出方法・修正指示 | フロー全体像・実装手順 |
| Phase 5 | 実装手順・worktree 管理・PR 作成方法 | フロー全体像・ドキュメント生成手順 |
| Phase 6 | テスト実行手順・失敗時エスカレーション | フロー全体像・実装手順 |
| Phase 7-8 | 準拠チェック手順・完了条件・最終コミット指示 | フロー全体像・実装手順 |

```
Agent(
  name: "{エージェント name}",
  model: "{モデル}",
  run_in_background: false,
  prompt: """
あなたは {フェーズ名} を担当するエージェントです。

作業ディレクトリ: {pwd の結果}
状態ファイル: doc/process/state.json
引数: {ARGS}
開発モード: {mode} / baseline_commit: {baseline_commit}

## 実行する手順
{スキル内容の該当フェーズ手順}
"""
)
```

**モデル指定のルール:**

- 上のフェーズ対応表に書かれた `モデル` 列は、各下流スキルの frontmatter (`model:`) と一致しており、その値をそのまま `Agent(model=…)` に渡す
- スキル frontmatter のモデルは**スキル作者が品質とコストを勘案して選択した値**であり、オーケストレーター側で勝手に上書きしない
- 上書きが必要な場合（例: テスト目的・ユーザー指定）は AskUserQuestion で人間に確認してから変更する
- フェーズ対応表とスキル frontmatter が食い違っている場合はスキル frontmatter を信頼し、表側を修正する

**フェーズ間依存関係と run_in_background:**

| フェーズ | 並列実行可否 | run_in_background |
|---|---|---|
| Phase 1-2〜4.5 | 不可（直列） | false |
| Phase 5 各グループ | グループ間は可 | PR マージ待機中のみ true |
| Phase 6〜7-8 | 不可（直列） | false |

Phase 5 で並列化する場合は `active_worktrees` に追加し SendMessage 完了通知を待つ。Cross グループは直列。

**Phase 5 PR マージ待機の責任分担:**

| アクター | 責任 |
|---|---|
| `phase-impl-agent`（サブエージェント） | グループの実装完了後に `gh pr create` で PR を作成し、PR 番号を `phase_5_progress.pr_numbers["group-N"]` へ書き込んでから完了通知を返す |
| `dev-flow` オーケストレーター | 完了通知を受けたら `pr_numbers` を読み、`gh pr view <N> --json state` を60秒間隔でポーリング。`MERGED` を確認したら `completed_groups` に追加し、依存解決済みの次グループを起動 |
| 人間 | PR レビュー・マージ。30分経過してもマージされない場合は AskUserQuestion で確認する |

マージは**人間が手動で実施する前提**。オーケストレーターが自動マージすることは無い（`gh pr merge` を発行しない）。詳細は `~/.claude/skills/dev-flow/reference/state-schema.md` の「Phase 5 PR マージ待機ロジック」を参照。

### STEP 5: タスク完了 & チェックリスト更新 & 次フェーズへの移行判定

**0. 動的ゲート判定（Phase 5 のグループ完了通知時）:**

| confidence | needs_human_review | 動作 |
|---|---|---|
| ≥ 0.8 | false | 自動移行 |
| 0.5〜0.8 | false | 通知のみ表示して自動移行 |
| < 0.5 または — | true | AskUserQuestion で人間ゲート発動 |

`uncertainty_points` が空でない場合は `needs_human_review=true` として扱う。

**1.** `TaskUpdate(id, status: "completed")`

**2. チェックリスト更新:** `task_checklist.md` が存在する場合、完了フェーズ行の `[ ]` → `[x]` に更新して進捗を表示。

**3. 次フェーズ移行:**

| 完了フェーズ | 次の動作 |
|---|---|
| phase_2（Phase 1-2） | **手動確認**: 「要件定義完了。確認後 `/dev-flow` を実行してください。」 |
| phase_4 以降 | **自動移行**: STEP 2 に戻って次フェーズを自動実行（Phase 7-8 まで連続） |
| phase_4_5_mini | `current_phase` を `"phase_4_5"` に戻してから Phase 5 を再開 |

---

## エスカレーション

エスカレーションが必要な場合は `doc/process/escalation_{phase}_{timestamp}.md` を生成して AskUserQuestion で提示する。

フォーマット・recovery パス詳細は Read すること:
`~/.claude/skills/dev-flow/reference/escalation-format.md`

---

## エラーハンドリング

エラー対処の詳細は Read すること:
`~/.claude/skills/dev-flow/reference/error-handling.md`

主なケース: state.json 破損・Agent 起動失敗・サブエージェント停止・チェックリスト更新失敗
