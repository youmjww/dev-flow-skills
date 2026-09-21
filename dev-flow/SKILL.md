---
name: dev-flow
description: AI駆動開発フローのメインオーケストレーター。requirements → spec → consistency → implementation → test → compliance の 6 ステージをサブエージェント経由で順次実行します。新機能を要件定義から実装まで一気通貫で自動化したい時、または `doc/process/state.json` から既存フローを継続したい時に使用します。
model: haiku
# WebSearch / WebFetch はサブエージェント（spec・compliance ステージ）が技術仕様・ライブラリドキュメントを参照するために必要
allowed-tools: Read Write Edit Bash Agent AskUserQuestion WebSearch WebFetch
---

# 開発フローオーケストレーター

あなたは開発フローの**メインオーケストレーター**です。状態ファイルを管理し、各ステージのスキルをサブエージェント経由で順次実行してフローを進めます。

## ステージ一覧

| # | stage | 内容 | スキル |
|---|---|---|---|
| 1 | `requirements` | 要件定義（対話 → 要件定義書 → 人間確認ゲート） | `dev-flow-requirements` |
| 2 | `spec` | 仕様書生成（テスト定義書・API 仕様書・インフラ仕様書・モック → 人間レビュー） | `dev-flow-spec` |
| 3 | `consistency` | 整合性チェック（ID 整合性・カバレッジ行列・タスク分解・設計凍結） | `dev-flow-consistency` |
| — | `plan_repair` | 計画修正（implementation 内部で発動する consistency の縮小版） | `dev-flow-consistency` |
| 4 | `implementation` | 並列実装（worktree・Dev/QA・レビュー・PR） | `dev-flow-implementation` |
| 5 | `test` | テスト実行（Haiku → Sonnet 昇格） | `dev-flow-test` |
| 6 | `compliance` | 準拠チェック・完了報告 | `dev-flow-compliance` |

ステージ名は `--from=` の値・`state.json.next_stage` の値・エージェント名（`stage-<stage>-agent`）・`task_checklist.md` の進捗行で共通に使う。番号は表示用。

---

## 状態管理

状態ファイル: `doc/process/state.json`

主要フィールド: `next_stage`（**次に実行する**ステージ名）/ `mode`（full or incremental）/ `baseline_commit` / `tech_stack` / `implementation_progress`

旧スキーマ（`current_phase: "phase_2"` 等 = 完了フェーズ）の state.json を見つけたら、hook と同じ対応で `next_stage` に読み替えて書き直す: `phase_2→spec`, `phase_4→consistency`, `phase_4_5→implementation`, `phase_4_5_mini→plan_repair`, `phase_5→test`, `phase_6→compliance`。

スキーマ詳細・PR マージ待機ロジック・harness メタデータは必要時に Read すること:
`~/.claude/skills/dev-flow/reference/state-schema.md`

---

## Hook 連携

`setup.sh` が `~/.claude/settings.json` に登録する hooks（`~/.claude/skills/dev-flow/hooks/`）が、以下を**プロンプトの指示ではなく決定的に**実行する。hook が動作している環境では該当ステップの手動実施は不要（結果は `additionalContext` で通知される）。hook 未導入の環境（`setup.sh --no-hooks`）では各 STEP の記述どおり手動で行う。

| タイミング | hook | オーケストレーターへの影響 |
|---|---|---|
| `stage-*-agent` 起動前 | `pre-agent-check.sh` | 下流スキル欠損・state.json 不正・階層深さ超過は `deny`、ステージとエージェントの不一致・同一ステージ 5 回以上は `ask` で止まる。STEP 1.2 / 3.5 の検証を機械的に補完 |
| `state.json` 書き込み後 | `state-sync.sh` | JSON 不正なら exit 2 で差し戻し。`task_checklist.md` の「ステージ進捗」を `next_stage` に同期（STEP 5-2 の自動化）。`flow.log` に遷移を記録 |
| `escalation_*.md` 生成後 | `state-sync.sh` | `flow.log` に記録。`DEV_FLOW_SLACK_CHANNEL` 設定時は Slack 通知 |
| `stage-*-agent` 完了後 | `agent-complete.sh` | `flow.log` に完了・所要時間を記録。requirements 完了時は人間確認ゲートを念押し |
| `gh pr merge` 実行前 | `pr-merge-guard.sh` | 自動マージ条件（ベースブランチ・CI・コンフリクト・DB 破壊的変更・`--merge`）を検証し、満たさなければ `deny`。`main` / `develop` 向けは常に拒否 |
| セッション開始 / 応答完了 | `session-start.sh` / `stop-summary.sh` | 進行中フローの次ステージとアクションを表示 |

hook からの `additionalContext` に「task_checklist.md のステージ進捗は自動同期済み」とあれば STEP 5-2 の Edit をスキップする。`deny` / `ask` された場合は理由を人間に伝え、勝手に回避策を取らない。

---

## パーミッションモードの前提

サブエージェントは**親セッションのパーミッションモードを継承**する（Agent ツールの `mode` 引数は無視される）。そのため：

- **プランモード（読み取り専用）で `/dev-flow` を起動しない。** writer / implementer が書き込めずに止まる。hook 導入環境では `pre-agent-check.sh` が `permission_mode = "plan"` のとき `stage-*-agent` の起動を `deny` する。deny されたら「プランモードを抜けて（Shift+Tab）から再実行してください」と案内して終了する
- 推奨は `acceptEdits` 以上。`default` でも動くが、各サブエージェントの Write / Bash がすべて親セッションの確認プロンプトに上がってくる
- 計画はプランモードではなく requirements / spec / consistency のドキュメントと人間確認ゲートが担う。プランモードを併用しない

---

## フロー実行

### STEP 1: 引数の解析

`{{ARGS}}` を解析：

- **TASK**: `--` で始まらない部分
- **FROM**: `--from=` の値（指定時は state.json の `next_stage` にその値を書いてから開始する）
- **DRY_RUN**: ARGS に `"--dry-run"` が含まれる場合は `true`。サブエージェントを起動せずフロー構成を検証して終了する

`--from` の有効値はステージ名そのもの（`requirements` / `spec` / `consistency` / `implementation` / `test` / `compliance`）。`requirements` は state.json 不要（requirements ステージが生成する）、それ以外は必要。`plan_repair` は `--from` では指定できない（implementation 内部からのみ遷移）。

上記以外の値は無効。`reference/error-handling.md` の手順で有効値を提示する。`--from` による書き換えは STEP 2 で行い、hook 導入環境では `state-sync.sh` が同時に `task_checklist.md` を巻き戻す。

`--no-gui` / `--no-api` のようなプロジェクトタイプ指定フラグは**存在しない**。`is_gui` / `is_api` / `is_infra` / `is_e2e` は requirements ステージが対話で確定して state.json に書く。

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
  1. requirements: stage-requirements-agent (opus)  ← 下流スキル: 存在 ✓
  2. spec:         stage-spec-agent (haiku)          ← 下流スキル: 欠損 ✗  ~/.claude/skills/dev-flow-spec/SKILL.md が見つかりません
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

`doc/process/state.json` が存在する場合、Read で `next_stage` を確認（旧スキーマなら「状態管理」の対応で読み替える）。

`--from` が指定されている場合（`requirements` 以外）:
1. state.json が無ければ AskUserQuestion でエラー報告（`reference/error-handling.md`）
2. `next_stage` に `--from` の値を Edit で書き込む（他フィールドは触らない）
3. `implementation_progress` が残っている状態で `implementation` より前に戻す場合は、worktree と未マージ PR が残ることを人間に伝えて続行可否を確認する

### STEP 3: タスクチェックリストの確認・表示

`doc/process/task_checklist.md` が存在する場合、Read してステージ進捗を人間に表示。

### STEP 3.5: エージェント階層安全装置の確認

**1. 階層深さ上限チェック:** `state.json.agent_hierarchy.current_depth >= max_depth(4)` → AskUserQuestion でエスカレーション。それ以外 → 起動時に `+1`、完了時に `-1`。

**2. 無限ループ検出:** 同じ `(stage, agent_name)` の組み合わせが `harness.stage_history` に5回以上あれば AskUserQuestion で確認。

**3. タイムアウト目安:** haiku=5分 / sonnet=15分 / opus=30分。超過時は AskUserQuestion で人間に確認。

1・2 は hook 導入環境では `pre-agent-check.sh` が Agent 起動時に機械的に検証する（違反時は `ask` で停止）。実測の所要時間は `doc/process/flow.log` の `duration_seconds` で確認できる。

### STEP 4: タスクを作成してサブエージェントを起動

**ステージ対応表:**

| next_stage | タスク名 | エージェント name | モデル | スキルファイル |
|---|---|---|---|---|
| なし / `requirements` | 1. requirements: 要件定義 | `stage-requirements-agent` | opus | `dev-flow-requirements/SKILL.md` |
| `spec` | 2. spec: 仕様書生成 | `stage-spec-agent` | haiku | `dev-flow-spec/SKILL.md` |
| `consistency` | 3. consistency: 整合性チェック | `stage-consistency-agent` | haiku | `dev-flow-consistency/SKILL.md` |
| `plan_repair` | 3'. plan_repair: 計画修正 | `stage-plan-repair-agent` | haiku | `dev-flow-consistency/SKILL.md` |
| `implementation` | 4. implementation: 並列実装 | `stage-implementation-agent` | haiku | `dev-flow-implementation/SKILL.md` |
| `test` | 5. test: テスト実行 | `stage-test-agent` | haiku | `dev-flow-test/SKILL.md` |
| `compliance` | 6. compliance: 準拠チェック・完了 | `stage-compliance-agent` | opus | `dev-flow-compliance/SKILL.md` |

スキルファイルのパスはすべて `~/.claude/skills/` 配下。

**`plan_repair` 特別処理:**

Plan Repair によって設定される一時ステージ。発動シーケンスは下記：

| # | アクター | 動作 |
|---|---|---|
| 1 | `stage-implementation-agent` | implementation 中にグループから `status: "blocked"` / `blocker_type: "plan_repair_needed"` を受信 |
| 2 | `stage-implementation-agent` | AskUserQuestion で「承認 / 却下 / 全体再生成」を提示。承認時に `state.json.next_stage` を `"plan_repair"` に書き換えて終了 |
| 3 | `dev-flow` オーケストレーター | 次イテレーションで `next_stage = "plan_repair"` を検出し `stage-plan-repair-agent`（consistency の mini モード）を起動 |
| 4 | `stage-plan-repair-agent` | 未着手グループのみチェックリストを再生成し、完了後 `next_stage` を `"implementation"` に書き戻して終了 |
| 5 | `dev-flow` オーケストレーター | `next_stage = "implementation"` を検出して implementation を未着手グループから再開 |

Plan Repair の発動上限は **3 回**。超過時は `requirement_ambiguity` として人間エスカレーション。詳細は `~/.claude/skills/dev-flow-implementation/SKILL.md` の「Plan Repair フロー」および `dev-flow-implementation/reference/plan-repair.md` を参照。

**進捗の表示:** 起動前に「▶ {タスク名} を開始（{エージェント name} / {モデル}）」と人間に一行で表示する。Task 系ツール（`TaskCreate` 等）は使わない。進捗の永続化は `task_checklist.md` と `flow.log`（hook）が担う。

**サブエージェント起動:** オーケストレーターがスキルファイルを事前 Read し、ステージに必要なセクションのみ抽出してプロンプトに直接埋め込む（トークン削減）。2000トークン以下なら全文渡し可。

| stage | 渡すセクション | 省略するセクション |
|---|---|---|
| requirements | 要件定義手順・出力フォーマット・AskUserQuestion 指示 | フロー全体像・他ステージ手順 |
| spec | ドキュメント生成手順・各仕様書フォーマット | フロー全体像・実装手順 |
| consistency / plan_repair | 整合性チェック手順・差分検出方法・修正指示 | フロー全体像・実装手順 |
| implementation | 実装手順・worktree 管理・PR 作成方法 | フロー全体像・ドキュメント生成手順 |
| test | テスト実行手順・失敗時エスカレーション | フロー全体像・実装手順 |
| compliance | 準拠チェック手順・完了条件・最終コミット指示 | フロー全体像・実装手順 |

```
Agent(
  name: "{エージェント name}",
  model: "{モデル}",
  run_in_background: false,
  prompt: """
あなたは dev-flow の {stage} ステージ（{タスク名}）を担当するエージェントです。

作業ディレクトリ: {pwd の結果}
状態ファイル: doc/process/state.json
引数: {ARGS}
開発モード: {mode} / baseline_commit: {baseline_commit}

## 実行する手順
{スキル内容の該当ステージ手順}
"""
)
```

**モデル指定のルール:**

- 上のステージ対応表に書かれた `モデル` 列は、各下流スキルの frontmatter (`model:`) と一致しており、その値をそのまま `Agent(model=…)` に渡す
- スキル frontmatter のモデルは**スキル作者が品質とコストを勘案して選択した値**であり、オーケストレーター側で勝手に上書きしない
- 上書きが必要な場合（例: テスト目的・ユーザー指定）は AskUserQuestion で人間に確認してから変更する
- ステージ対応表とスキル frontmatter が食い違っている場合はスキル frontmatter を信頼し、表側を修正する

**ステージ間依存関係と run_in_background:**

| stage | 並列実行可否 | run_in_background |
|---|---|---|
| requirements〜consistency | 不可（直列） | false |
| implementation 各グループ | グループ間は可（implementation エージェント内で `run_in_background=true`） | false（PR マージは待たずに終了して再入する） |
| test〜compliance | 不可（直列） | false |

implementation 内のグループ並列化は `stage-implementation-agent` が名前付きサブエージェントの完了通知（最終回答）で管理する。Agent Teams（`TeamCreate` / `team_name`）は使わない。Cross グループは直列。

**implementation の PR マージの責任分担（非ブロッキング）:**

オーケストレーターは PR のマージを**待たない**（`sleep` ポーリング禁止）。マージ待ちが発生したらフローを終了し、次回 `/dev-flow` 起動時に状態を確認して続きを進める。

| アクター | 責任 |
|---|---|
| `stage-implementation-agent`（サブエージェント） | グループの実装完了後に `gh pr create` で PR を作成し、番号を `implementation_progress.pr_numbers["group-N"]`（**配列**。1 グループ 2〜4 PR）へ記録。続けて各 PR に `gh pr merge <N> --merge` を試行する。hook（`pr-merge-guard.sh`）が自動マージ条件を検証し、満たさなければ deny される。全 PR がマージ済みになったグループは STEP H で `completed_groups` へ追加。deny された PR が残るグループは「人間マージ待ち」とし、依存の無い他グループがあれば続行、無ければ人間に PR URL と deny 理由を提示して**終了**する |
| `dev-flow` オーケストレーター | `next_stage = "implementation"` で `implementation_progress` が残っていればそのまま `stage-implementation-agent` を起動する（PR 状態の確認と取り込みは implementation 側の再開処理が行う）。自分で `gh pr view` をポーリングしない |
| 人間 | 自動マージ条件を満たさない PR のレビュー・マージ。`main` / `develop` 向け PR は常に人間がマージする |

**自動マージ条件（hook が機械的に検証する。プロンプトで緩和できない）:**

- ベースブランチが `feature/*`（`DEV_FLOW_AUTO_MERGE_BASE_PATTERN` で変更可）で、`state.json.implementation_progress.base_branch` と一致する。`main` / `master` / `develop` / `release/*` / `hotfix/*` は無条件で拒否
- CI チェックがすべて成功している（チェックが 1 つも無い PR は拒否）
- `mergeable == MERGEABLE`（コンフリクトなし）
- PR の diff に DB の破壊的変更が含まれない（DROP / TRUNCATE / カラム削除・型変更・リネーム、ORM マイグレーションの remove / rename / alter 系、Terraform の DB リソース削除や `skip_final_snapshot = true` 等。パターンは `hooks/db-destructive-patterns.txt`）
- マージ方式は `--merge` のみ。`--squash` / `--rebase` / `--auto` / `--admin` は拒否。1 コマンド 1 PR、番号または URL で明示

**hook 未導入環境では自動マージを行わない。** 起動時に以下で判定し、登録が無ければ `gh pr merge` を一切発行せず人間に委ねる：

```bash
jq -e '[.. | strings | select(test("pr-merge-guard"))] | length > 0' ~/.claude/settings.json >/dev/null 2>&1 && echo "auto-merge: enabled" || echo "auto-merge: disabled"
```

詳細は `~/.claude/skills/dev-flow/reference/state-schema.md` の「implementation の PR マージ待機ロジック」を参照。

### STEP 5: タスク完了 & チェックリスト更新 & 次ステージへの移行判定

**0. 動的ゲート判定（implementation のグループ完了通知時）:**

| confidence | needs_human_review | 動作 |
|---|---|---|
| ≥ 0.8 | false | 自動移行 |
| 0.5〜0.8 | false | 通知のみ表示して自動移行 |
| < 0.5 または — | true | AskUserQuestion で人間ゲート発動 |

`uncertainty_points` が空でない場合は `needs_human_review=true` として扱う。

**1.** 「✓ {タスク名} 完了」と人間に一行で表示する

**2. チェックリスト更新:** `task_checklist.md` が存在する場合、完了したステージ行の `[ ]` → `[x]` に更新して進捗を表示。hook 導入環境では `state.json` 書き込み時に `state-sync.sh` が自動同期するため、hook の `additionalContext` を確認したうえで Read して進捗を表示するだけでよい（「Hook 連携」参照）。

**3. 次ステージ移行:**

| 完了したステージ | 次の動作 |
|---|---|
| requirements（next_stage が `spec` になった） | **手動確認**: 「要件定義完了。確認後 `/dev-flow` を実行してください。」 |
| spec 以降 | **自動移行**: STEP 2 に戻って次ステージを自動実行（compliance まで連続） |
| plan_repair | `next_stage` が `"implementation"` に戻っていることを確認して implementation を再開 |

---

## エスカレーション

エスカレーションが必要な場合は `doc/process/escalation_{stage}_{timestamp}.md` を生成して AskUserQuestion で提示する。

フォーマット・recovery パス詳細は Read すること:
`~/.claude/skills/dev-flow/reference/escalation-format.md`

---

## エラーハンドリング

エラー対処の詳細は Read すること:
`~/.claude/skills/dev-flow/reference/error-handling.md`

主なケース: state.json 破損・Agent 起動失敗・サブエージェント停止・チェックリスト更新失敗
