# Plan Repair フロー詳細

`dev-flow-implementation/SKILL.md` STEP C で `blocker_type: "plan_repair_needed"` を受信したときに実行する手順の詳細。

## Contents
- 発動上限
- ユーザー提示フォーマット
- 選択肢別の動作
- 修正履歴の記録

## 発動上限

Plan Repair の発動は同一フロー内で最大3回まで。上限到達後は `plan_repair_needed` を `requirement_ambiguity` として処理（人間にエスカレーション）。

## 手順

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
   - Phase 4.5 を mini モードで実行（詳細は `dev-flow-consistency/SKILL.md` 参照）
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

## パース失敗時のフォールバック

JSON パースに失敗した場合は、テキストに「実装完了」が含まれれば `completed` 扱い、「ブロッカー」または「blocked」が含まれれば `blocked` 扱いとする。
