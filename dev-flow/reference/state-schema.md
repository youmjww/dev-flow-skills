# state.json スキーマ詳細

`doc/process/state.json` の完全なスキーマと各フィールドの説明。

## 完全スキーマ

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
    },
    "pr_numbers": {
      "group-1": 101,
      "group-2": null,
      "group-3": null
    }
  },
  "agent_hierarchy": {
    "max_depth": 4,
    "current_depth": 1,
    "stack": ["dev-flow"]
  },
  "harness": {
    "skill_versions": {
      "dev-flow": "{git rev-parse --short HEAD}"
    },
    "started_at": "{ISO8601}",
    "phase_history": [
      { "phase": "phase_2", "model": "claude-opus-4-7", "started_at": "...", "completed_at": "...", "duration_seconds": 320 }
    ]
  }
}
```

## フィールド説明

| フィールド | 説明 |
|---|---|
| `current_phase` | 次に実行するフェーズ。`null` または欠損 = Phase 1 から開始 |
| `mode` | `"full"`（新規）/ `"incremental"`（差分のみ） |
| `baseline_commit` | `incremental` 時のみ設定。設定主体・更新主体・参照範囲は下記「baseline_commit のライフサイクル」を参照 |
| `tech_stack` | 言語・フレームワーク等。Phase 3 以降のサブエージェントが参照 |
| `is_gui/is_api/is_infra/is_e2e` | 対応するフェーズを有効化するフラグ |
| `phase_5_progress` | Phase 5 実行中のみ存在。完了時に削除 |
| `phase_5_progress.pr_numbers` | 各グループの PR 番号。PR 作成後に phase-impl-agent が書き込む |
| `agent_hierarchy` | 階層深さ監視。max_depth=4 を超えたらエスカレーション |
| `harness` | 再現性メタデータ。Phase 1 開始時に追加、各フェーズ完了時に phase_history を更新 |

## baseline_commit のライフサイクル

`mode = "incremental"` の差分計算に使うコミット SHA。誰が読み・書きするかを明確にする：

| タイミング | アクター | 動作 |
|---|---|---|
| 初期設定 | `dev-flow` オーケストレーター（STEP 1.5） | `incremental` モード確定時に `git rev-parse HEAD` を `baseline_commit` に記録 |
| Phase 4.4 | `phase-consistency-agent`（Impact Analysis） | `git diff $baseline_commit...HEAD -- doc/` で要件差分を抽出。**書き換えない** |
| Phase 5 開始時 | `phase-impl-agent` | 実装範囲決定のために参照。**書き換えない** |
| Phase 5 完了時 | `phase-impl-agent` | 全グループの PR がマージされた後、`git rev-parse HEAD`（=ベースブランチの最新 HEAD）を `baseline_commit` に書き戻して state.json を保存 |
| Phase 6 / Phase 7-8 | 参照しない | テスト・準拠チェックは `baseline_commit` に依存しない |

`full` モードでは `baseline_commit = null` 固定。すべてのアクターは null を見たら「全範囲対象」と解釈する。

## skill_versions の取得

```bash
git -C ~/.claude/skills/dev-flow rev-parse --short HEAD 2>/dev/null || echo "unknown"
```

## Phase 5 PR マージ待機ロジック

`completed_groups` への追加タイミングは「PR マージ後」。待機方針：

| 状況 | 動作 |
|---|---|
| PR が Open | `pr_numbers` から番号を取得してポーリング（60秒間隔） |
| マージ確認後 | `completed_groups` に追加して次グループへ |
| 30分経過 | AskUserQuestion で人間に確認 |
| 新グループ追加 | 非対応。Phase 4.5 からやり直し |

PR 番号取得例：
```bash
PR_NUMBER=$(jq -r '.phase_5_progress.pr_numbers["group-2"]' doc/process/state.json)
until gh pr view "$PR_NUMBER" --json state --jq '.state' | grep -q MERGED; do
  sleep 60
done
```
