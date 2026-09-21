# state.json とリモート真実の乖離からの復旧


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

1. `state.json` の `implementation_progress.completed_groups` に当該グループを追加
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

出力を元に `implementation_progress.completed_groups` を再構築し、`state.json` を手動または自動で復元する。

