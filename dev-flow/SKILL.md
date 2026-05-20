---
name: dev-flow
description: AI駆動開発フローのメインオーケストレーター。要件定義→ドキュメント生成→整合性チェック→並列実装→テスト→準拠チェックの全フェーズをサブエージェント経由で順次実行します。新機能を要件定義から実装まで一気通貫で自動化したい時、または `doc/process/state.json` から既存フローを継続したい時に使用します。
model: haiku
allowed-tools: Read Write Edit Bash Agent TaskCreate TaskUpdate AskUserQuestion WebSearch WebFetch
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
- `baseline_commit`: `incremental` 時のみ設定。要件追加前の最新コミットハッシュ。Phase 4.5 でここを基点にドキュメントと既存コードの差分を検出する。**Phase 5 完了時に `git rev-parse HEAD` で最新コミットハッシュに更新すること**（次回の incremental サイクルで不要な差分を再処理しないため）
- `phase_5_progress` は Phase 5 実行中のみ存在し、Phase 5 完了時に削除されます。

**Phase 5 の PR マージ待機ロジック:**

`phase_5_progress.completed_groups` に各グループが追加されるタイミングは「そのグループの PR がマージされた後」とする。マージ待機は以下の方針で行う：

| 状況 | 動作 |
|---|---|
| グループの PR が Open の間 | `gh pr view {PR番号} --json state` で定期確認（ポーリング間隔 60 秒）。Monitor ツールが利用可能な場合は Monitor で検出する |
| マージ確認後 | `completed_groups` に追加して次グループへ進む |
| 30 分経過してもマージされない | AskUserQuestion で人間に確認（「PR #{番号} がマージされていません。続行しますか？」） |
| 新グループの追加 | Phase 5 実行中に新グループを追加することは**非対応**。Phase 4.5 からやり直すこと |

**再現性メタデータ（`harness` セクション）:**

フロー開始時（Phase 1 開始時）に以下の `harness` セクションを追加し、各フェーズ完了時に `phase_history` を更新します：

```json
{
  "harness": {
    "skill_versions": {
      "dev-flow": "{git rev-parse --short HEAD}",
      "dev-flow-implementation": "{同上}"
    },
    "started_at": "{ISO8601 タイムスタンプ}",
    "phase_history": [
      {
        "phase": "phase_2",
        "model": "claude-opus-4-7",
        "started_at": "...",
        "completed_at": "...",
        "duration_seconds": 320
      }
    ]
  }
}
```

`skill_versions` は以下で取得：
```bash
git -C ~/.claude/skills/dev-flow rev-parse --short HEAD 2>/dev/null || echo "unknown"
```

各フェーズ開始時に `started_at` を記録し、完了時に `completed_at` と `duration_seconds` を計算して `phase_history` に追加します。

---

## フロー実行

### STEP 1: 引数の解析

`{{ARGS}}` を解析：

- **TASK**: タスクの説明（`--` で始まらない部分）
- **FROM**: 開始フェーズ（`--from=` の値）
  - 指定あり → state.json の current_phase を無視して指定フェーズから強制開始（state.json が必要）
  - 指定なし → STEP 2 の current_phase に従う
- **DRY_RUN**: `--dry-run` フラグ（実際のサブエージェントを起動せず、フロー構成の事前検証のみ行う）

`--from` の値と対応フェーズ：

| `--from` 値 | 開始フェーズ | state.json 要否 |
|---|---|---|
| `requirements` または 未指定かつ state.json なし | Phase 1 | 不要 |
| `spec` | Phase 3 | 必要 |
| `parallel` | Phase 5 | 必要 |
| `test` | Phase 6 | 必要 |
| `sync` | Phase 7 | 必要 |

`--from` 指定時に state.json が存在しない場合は AskUserQuestion で人間にエラーを報告する。

**`--dry-run` 指定時の動作:**

サブエージェントを起動せず、以下の検証結果のみを出力して終了する：

1. state.json の存在・フォーマット確認（存在する場合）
2. 全下流スキルファイルの存在確認
3. `tech_stack` の主要フィールド確認（state.json がある場合）
4. 実行予定フェーズ・使用モデルの一覧表示

```
[dry-run] 実行計画:
  Phase 1-2: phase-requirements-agent (opus)  ← 下流スキル: 存在 ✓
  Phase 3-4: phase-spec-agent (haiku)          ← 下流スキル: 存在 ✓
  Phase 4.5: phase-consistency-agent (haiku)   ← 下流スキル: 存在 ✓
  Phase 5:   phase-impl-agent (haiku)          ← 下流スキル: 存在 ✓
  Phase 6:   phase-test-agent (haiku)          ← 下流スキル: 存在 ✓
  Phase 7-8: phase-compliance-agent (opus)     ← 下流スキル: 存在 ✓
```

### STEP 1.2: 下流スキルファイルの事前検証

STEP 1 の直後（`--dry-run` の有無に関わらず）に、使用する全下流スキルファイルの存在を確認する：

```bash
ls ~/.claude/skills/dev-flow-requirements/SKILL.md \
   ~/.claude/skills/dev-flow-spec/SKILL.md \
   ~/.claude/skills/dev-flow-consistency/SKILL.md \
   ~/.claude/skills/dev-flow-implementation/SKILL.md \
   ~/.claude/skills/dev-flow-test/SKILL.md \
   ~/.claude/skills/dev-flow-compliance/SKILL.md 2>&1
```

存在しないファイルがある場合は、そのフェーズに到達する前に早期エラーとして AskUserQuestion で報告して中断する。`--dry-run` でない場合も同様に実行時より早い段階で検知できる。

### STEP 1.5: 開発モードの判定（state.json が存在しない場合のみ）

STEP 1 の後、STEP 2 の state.json 読み込み前に実行します。  
**state.json が存在する場合はスキップ**（既存フローの継続のため、mode は state.json の値を使う）。

**1. 既存実装の確認：**

ディレクトリ名だけでは空ディレクトリ・.gitkeep を誤検知するため、gitで追跡されているソースコードファイルの存在をファイル数で判定する：

```bash
git log --oneline -1 2>/dev/null
# ソースコードファイルが1件以上 git 追跡されているか確認
git ls-files | grep -cE '\.(go|py|ts|tsx|js|jsx|rb|java|rs|kt|swift|c|cpp|cs)$' 2>/dev/null || echo 0
```

- 上記コマンドの出力が `1` 以上 → 実装コードあり
- `0` または git 管理外 → 実装コードなし（`"full"` モード確定）

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

### STEP 3.5: エージェント階層安全装置の確認

サブエージェントを起動する前に、以下の安全装置を確認します：

**1. 階層深さの上限チェック:**

`state.json` に `agent_hierarchy` セクションが存在する場合、`current_depth` を確認します：

```json
{
  "agent_hierarchy": {
    "max_depth": 4,
    "current_depth": 1,
    "stack": ["dev-flow"]
  }
}
```

- `current_depth >= max_depth` → AskUserQuestion で人間に報告してエスカレーション
- それ以外 → サブエージェント起動時に `current_depth + 1` に更新して `stack` に追加

サブエージェント完了後は `current_depth - 1` に戻し、`stack` から削除します。

**2. 無限ループ検出（Plan Repair / 動的ゲートの組み合わせ時）:**

同一フロー内で同じ `(phase, agent_name)` の組み合わせが5回以上発動していた場合は無限ループの可能性があります。`state.json` の `harness.phase_history` を確認し、同じフェーズが繰り返し記録されていれば AskUserQuestion で人間に確認します。

**3. モデル別デフォルトタイムアウト（参考値）:**

| モデル | 推奨タイムアウト目安 |
|---|---|
| haiku | 5分 |
| sonnet | 15分 |
| opus | 30分 |

エージェントが推定時間を大幅に超えた場合は AskUserQuestion で人間に状況を確認します。

**Monitor によるタイムアウト検出（Phase 5 のグループ PR マージ待機時）:**

Phase 5 でグループ PR のマージを待機する場合は、以下の Monitor パターンで定期確認します：

```bash
# PR マージ待機ループ（until で条件成立まで繰り返す）
until gh pr view {PR番号} --json state --jq '.state' | grep -q MERGED; do
  sleep 60
done
echo "MERGED"
```

このコマンドを `run_in_background: true` の Bash で起動し、完了通知を受け取るまで他の処理（人間への報告など）を行います。30 分（1800 秒）を超えてもマージされない場合は AskUserQuestion で確認します。

### STEP 4: タスクを作成してサブエージェントを起動

実行するフェーズに対応するタスクを **TaskCreate** で作成してから、サブエージェントを起動します。

| current_phase | タスク名 | エージェント name | モデル | 使用するスキルファイル |
|---|---|---|---|---|
| なし（初回） | Phase 1-2: 要件定義 | `phase-requirements-agent` | opus | `~/.claude/skills/dev-flow-requirements/SKILL.md` |
| phase_2 | Phase 3-4: ドキュメント生成 | `phase-spec-agent` | haiku | `~/.claude/skills/dev-flow-spec/SKILL.md` |
| phase_4 | Phase 4.5: 整合性チェック | `phase-consistency-agent` | haiku | `~/.claude/skills/dev-flow-consistency/SKILL.md` |
| phase_4_5 | Phase 5: 並列実装 | `phase-impl-agent` | haiku | `~/.claude/skills/dev-flow-implementation/SKILL.md` |
| phase_4_5_mini | Phase 4.5（mini）: 計画修正 | `phase-consistency-mini-agent` | haiku | `~/.claude/skills/dev-flow-consistency/SKILL.md` |
| phase_5 | Phase 6: テスト実行 | `phase-test-agent` | haiku | `~/.claude/skills/dev-flow-test/SKILL.md` |
| phase_6 | Phase 7-8: 準拠チェック・完了 | `phase-compliance-agent` | opus | `~/.claude/skills/dev-flow-compliance/SKILL.md` |

**`phase_4_5_mini` の特別処理:**

`phase_4_5_mini` は Phase 5 中の Plan Repair によって一時的に設定されます。通常フローとは異なり、以下の動作をします：

1. `phase-impl-agent` の STEP C 内で Plan Repair フローが判断し、`state.json.current_phase` を `"phase_4_5_mini"` に設定
2. このオーケストレーターは `phase_4_5_mini` を検出したら `phase-consistency-mini-agent` を起動（mini モードでスキルファイルを実行）
3. mini モード完了後、`state.json.current_phase` は `"phase_4_5"` に戻る
4. STEP 5 の移行判定では `phase_4_5` として扱い、Phase 5 を未着手グループから再開する

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

**フェーズ別：渡すべきセクションと省略するセクション:**

| フェーズ | 渡すセクション | 省略するセクション |
|---|---|---|
| Phase 1-2（要件定義） | 要件定義手順・出力フォーマット・AskUserQuestion 指示 | フロー全体像・他フェーズの手順 |
| Phase 3-4（ドキュメント生成） | ドキュメント生成手順・各仕様書フォーマット | フロー全体像・実装手順 |
| Phase 4.5（整合性チェック） | 整合性チェック手順・差分検出方法・修正指示 | フロー全体像・実装手順 |
| Phase 5（並列実装） | 実装手順・worktree 管理・PR 作成方法・グループ別タスク | フロー全体像・ドキュメント生成手順 |
| Phase 6（テスト実行） | テスト実行手順・失敗時のエスカレーション | フロー全体像・実装手順 |
| Phase 7-8（準拠チェック） | 準拠チェック手順・完了条件・最終コミット指示 | フロー全体像・実装手順 |

スキルファイルのトークン数目安：2000トークン以下なら全文渡し可。それ以上なら上記テーブルに従い必要セクションのみ抽出する。

**フォールバック**: スキルファイルのサイズが大きくプロンプトに収まらない場合は、従来通り Read ツールでの読み込みを指示するが、その場合もフェーズに関係ないセクション（フロー全体像など）は省略するよう指示すること。

**フェーズ間の依存関係と run_in_background 採用基準:**

| フェーズ | 依存フェーズ | 並列実行可否 | run_in_background |
|---|---|---|---|
| Phase 1-2 | なし | — | false |
| Phase 3-4 | Phase 1-2 完了後 | 不可（直列） | false |
| Phase 4.5 | Phase 3-4 完了後 | 不可（直列） | false |
| Phase 5 各グループ | Phase 4.5 完了後 | グループ間は**可** | グループ間の PR マージ待機中のみ true |
| Phase 6 | Phase 5 全グループ完了後 | 不可（直列） | false |
| Phase 7-8 | Phase 6 完了後 | 不可（直列） | false |

Phase 5 のグループ間並列化（`run_in_background: true`）を使う場合は、`active_worktrees` に追加してから SendMessage の完了通知を待ちます。ただし、グループ間に依存関係（`group_types` が Cross など）がある場合は直列とします。

### STEP 5: タスク完了 & チェックリスト更新 & 次フェーズへの移行判定

サブエージェント完了後、以下を順に実行します：

**0. 自己評価フィールドによる動的ゲート判定（Phase 5 の各グループ完了通知時）:**

Phase 5 のサブエージェントから届く JSON に `confidence` / `needs_human_review` フィールドが含まれる場合、以下のルールで動的に人間ゲートを発動します：

| confidence | needs_human_review | 動作 |
|---|---|---|
| ≥ 0.8 | false | 自動移行（通常フロー） |
| 0.5〜0.8 | false | 通知のみ表示して自動移行 |
| < 0.5 または — | true | **AskUserQuestion で動的に人間ゲートを発動** |

**動的ゲート発動時の AskUserQuestion 内容:**

```
## 実装エージェントから確認が必要な判断があります

エージェント: {agent}
自信度: {confidence}

### 不確実な判断
{uncertainty_points を箇条書きで表示}

どのように対処しますか？
- 「エージェントの判断を採用して続行」→ 次フェーズへ
- 「エージェントの判断を却下して修正指示」→ 修正内容を入力後、worktree で再実装
- 「判断をメモしてそのまま続行」→ uncertainty_points を doc/process/decision_log.md に記録して続行
```

**calibration の注意:** LLM の confidence は信頼性が低いため、`needs_human_review=true` を優先し、`confidence` 単独では自動移行判定の参考値とする。`uncertainty_points` が空でない場合は `needs_human_review=true` として扱う。

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
| phase_4_5_mini（Plan Repair） | phase_4_5_mini → Phase 5（再開） | **自動移行**：state.json の `current_phase` を `phase_4_5` に戻してから STEP 2 → Phase 5 を再開 |
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

## 全フェーズ共通エスカレーションフォーマット

各フェーズでエスカレーションが必要な場合（人間に判断を仰ぐ場合）は、以下の統一フォーマットで `doc/process/escalation_{phase}_{timestamp}.md` を生成してから AskUserQuestion で提示します：

```markdown
# エスカレーション報告: {Phase 名}

## 1. 試行履歴
| 試行 | モデル | 主な行動 | 結果 |
|---|---|---|---|
| 1 | haiku | （行動の概要） | （結果） |
| 2 | sonnet | （行動の概要） | （結果） |

## 2. 現在の状態
（残っている問題・未解決事項を箇条書き）

## 3. AIが判断できなかった理由
- [ ] 要件の曖昧さ（具体的にどこ）
- [ ] 仕様間の矛盾（どの仕様とどの仕様）
- [ ] 技術的制約（どの技術スタックの限界）
- [ ] その他: {自由記述}

## 4. 選択肢
| 選択肢 | 期待される結果 |
|---|---|
| A: （選択肢A） | （結果） |
| B: （選択肢B） | （結果） |

## 5. 推奨 recovery パス
（エスカレーション理由に応じて再開フェーズを提示）
```

**エスカレーション理由別の推奨 recovery パス:**

ユーザーが AskUserQuestion に回答した後、オーケストレーターは以下の基準で再開フェーズを決定します：

| エスカレーション理由 | ユーザー対処後の再開フェーズ | `--from` 値 |
|---|---|---|
| 要件の曖昧さ | Phase 1（要件定義からやり直し） | `requirements` |
| 仕様間の矛盾 | Phase 3-4（ドキュメント生成からやり直し） | `spec` |
| 技術的制約（実装不可） | Phase 4.5（整合性チェックで修正） | なし（state.json を `phase_4` に戻す） |
| テスト失敗 | Phase 5（対象グループのみ再実装） | `parallel` |
| その他 | 人間が `/dev-flow --from={適切な値}` で指定 | 人間が判断 |

このフォーマットは全フェーズ（Phase 1-2 の要件定義から Phase 7-8 の準拠チェックまで）で統一して使用してください。各フェーズのサブエージェントもこのフォーマットに従ってエスカレーション報告を行います。

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

