# エージェント起動前のプロンプト注入詳細

`dev-flow-implementation/SKILL.md` STEP B で各エージェントを起動する前に、プロンプトへ追加注入する要素の詳細仕様。

## Contents
- memory フィードバックの注入
- レビュー指摘・テスト失敗の memory 保存
- ファイルスコープガードレール
- Sonnet 昇格時のプロンプト追記

## memory フィードバックの注入

各エージェントを起動する前に、プロジェクトの memory ディレクトリから関連する feedback を読み込んでプロンプト冒頭に注入する。

```bash
MEMORY_DIR="~/.claude/projects/$(pwd | sed 's|/|-|g')/memory"
ls "${MEMORY_DIR}/feedback_review_infra.md" 2>/dev/null
ls "${MEMORY_DIR}/feedback_review_app.md" 2>/dev/null
ls "${MEMORY_DIR}/feedback_test_failures.md" 2>/dev/null
```

ファイルが存在する場合、プロンプトの先頭に以下を追記：

```
## 過去のレビューで指摘された再発項目（必ず確認してから実装・レビューすること）

{feedback_review_infra.md または feedback_review_app.md の内容}
```

## レビュー指摘・テスト失敗の memory 保存（STEP D / STEP H 後）

レビュー指摘が 3 回以上繰り返されたパターン、または人間によるマージ後修正があった場合、以下のフォーマットで memory に保存する：

```markdown
---
name: feedback-review-infra-{date}
description: Infra レビューで再発する指摘パターン（{date} 記録）
metadata:
  type: feedback
---

## 再発指摘パターン

- **{指摘カテゴリ}**: {具体的な指摘内容}
  - 発生回数: {N}回
  - 典型例: {コード例または説明}
  - 対処方法: {推奨する実装アプローチ}
```

## ファイルスコープガードレール

各エージェントには **作業対象ファイルパスの制約** を明示してプロンプトに含める：

| エージェント | 作業許可ディレクトリ | 禁止ディレクトリ例 |
|---|---|---|
| Dev (Infra) | `{MAIN_DIR}/../worktree-dev-infra-group-N/` 配下のインフラ関連ファイル | フロントエンド、アプリ層 |
| Dev (App) | `{MAIN_DIR}/../worktree-dev-app-group-N/` 配下のアプリ関連ファイル | Terraform、インフラ設定 |
| QA (Infra) | `{MAIN_DIR}/../worktree-qa-infra-group-N/` 配下のインフラテスト | アプリテスト |
| QA (App) | `{MAIN_DIR}/../worktree-qa-app-group-N/` 配下のアプリテスト | インフラテスト |

**プロンプトに追記する文言:**

```
【ファイルスコープ制限】
担当タスク（{DEV/QA_TASKS}）に直接関係するファイルのみ変更すること。
- 許可: {作業許可ディレクトリのパターン}（例: `*.tf`, `pkg/auth/**`, `tests/auth/**`）
- 禁止: 担当範囲外のファイル（例: フロントエンド、他チームのモジュール）

タスクに関係ないファイルを変更しそうになった場合は変更せず、代わりに SendMessage で "ファイルスコープ外の変更が必要" と報告してください。
```

## Sonnet 昇格時のプロンプト追記

```
【モデル昇格通知】
Haiku による修正試行が上限に達したか、設計レベルの指摘が含まれるため Sonnet に昇格しました。
以下のレビュー指摘履歴を参考に、より高度な判断で問題を解決してください。

### Haiku 試行履歴
{Haiku の試行回数と主な失敗内容}

### 未解決の指摘
{レビュアーからの指摘内容}
```
