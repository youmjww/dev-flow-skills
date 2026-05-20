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
| `baseline_commit` | incremental 時のみ設定。**Phase 5 完了時に最新 HEAD で更新すること** |
| `tech_stack` | 言語・フレームワーク等。Phase 3 以降のサブエージェントが参照 |
| `is_gui/is_api/is_infra/is_e2e` | 対応するフェーズを有効化するフラグ |
| `phase_5_progress` | Phase 5 実行中のみ存在。完了時に削除 |
| `phase_5_progress.pr_numbers` | 各グループの PR 番号。PR 作成後に phase-impl-agent が書き込む |
| `agent_hierarchy` | 階層深さ監視。max_depth=4 を超えたらエスカレーション |
| `harness` | 再現性メタデータ。Phase 1 開始時に追加、各フェーズ完了時に phase_history を更新 |

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
