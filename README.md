# dev-flow スキル集

Claude Code 用の AI 駆動開発フロースキルです。要件定義から実装・テスト・完了確認まで、一貫した開発フローを自動化します。

## セットアップ

```bash
git clone git@github.com:youmjww/dev-flow-skills.git ~/dev-flow-skills
bash ~/dev-flow-skills/setup.sh
```

`~/.claude/skills/` に各スキルへのシンボリックリンクが作成されます。

---

## 全体フロー

```
/dev-flow <タスク説明>
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 1-2: 要件定義  (/dev-flow-requirements)          │
│  - ユーザーと対話しながら要件を深掘り                   │
│  - 要件定義書を doc/requirements/ に生成                │
│                               モデル: Opus 4.7           │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 3-4: ドキュメント生成  (/dev-flow-spec)          │
│  - テスト定義書・API仕様書・UIモックを並列生成          │
│  - doc/test-spec/, doc/api-spec/, doc/mock/ に出力      │
│                               モデル: Haiku (子: Sonnet) │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 4.5: 整合性チェック  (/dev-flow-consistency)     │
│  - ドキュメント間の矛盾を検出                           │
│  - タスク分解・設計凍結                                 │
│                               モデル: Haiku (子: Opus)   │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 5: 並列実装  (/dev-flow-implementation)          │
│  - git worktree でグループ並列実装                      │
│  - 実装完了後に順次マージ                               │
│                               モデル: Haiku (子: Sonnet) │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 6: テスト実行  (/dev-flow-test)                  │
│  - Haiku でテスト実行（最大2回）                        │
│  - 2回失敗で Sonnet に自動昇格（最大3回）               │
│  - 解決不能なら人間にエスカレーション                   │
│                               モデル: Haiku → Sonnet     │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 7-8: 準拠チェック  (/dev-flow-compliance)        │
│  - 実装がドキュメントに準拠しているか確認               │
│  - 完了報告を生成                                       │
│                               モデル: Opus 4.7           │
└─────────────────────────────────────────────────────────┘
```

---

## 使い方

### 基本（最初から全フェーズ実行）

```
/dev-flow 新機能を実装したい
```

各フェーズ完了後に `/dev-flow` を実行するだけで次フェーズへ進みます。状態は `doc/process/state.json` で管理されるため、セッションをまたいでも継続できます。

### 特定フェーズから開始

```
/dev-flow --from=test
```

| オプション | 開始フェーズ |
|---|---|
| `--from=requirements` | Phase 1-2（要件定義） |
| `--from=spec` | Phase 3-4（ドキュメント生成） |
| `--from=consistency` | Phase 4.5（整合性チェック） |
| `--from=implementation` | Phase 5（実装） |
| `--from=test` | Phase 6（テスト） |
| `--from=compliance` | Phase 7-8（準拠チェック） |

### フェーズを単独実行

```
/dev-flow-requirements    # 要件定義のみ
/dev-flow-spec            # ドキュメント生成のみ
/dev-flow-consistency     # 整合性チェックのみ
/dev-flow-implementation  # 実装のみ
/dev-flow-test            # テストのみ
/dev-flow-compliance      # 準拠チェックのみ
```

### プロジェクトタイプ指定

```
/dev-flow API を実装 --no-gui   # API プロジェクト（UIモック不要）
/dev-flow 画面を実装 --no-api   # GUI プロジェクト（API仕様書不要）
```

---

## スキル構成

```
dev-flow-skills/
├── dev-flow/                    # メインオーケストレーター
│   ├── SKILL.md                 # オーケストレーターのエントリポイント
│   ├── phase-requirements.md    # Phase 1-2 の詳細定義
│   ├── phase-spec.md            # Phase 3-4 の詳細定義
│   ├── phase-consistency.md     # Phase 4.5 の詳細定義
│   ├── phase-implementation.md  # Phase 5 の詳細定義
│   ├── phase-test.md            # Phase 6 の詳細定義
│   ├── phase-compliance.md      # Phase 7-8 の詳細定義
│   └── workflow.mmd             # フロー図（Mermaid）
├── dev-flow-requirements/       # Phase 1-2 スキル
├── dev-flow-spec/               # Phase 3-4 スキル
├── dev-flow-consistency/        # Phase 4.5 スキル
├── dev-flow-implementation/     # Phase 5 スキル
├── dev-flow-test/               # Phase 6 スキル
├── dev-flow-compliance/         # Phase 7-8 スキル
└── setup.sh                     # シンボリックリンク作成スクリプト
```

---

## モデル構成

| フェーズ | スキル | モデル |
|---|---|---|
| オーケストレーター | dev-flow | Haiku 4.5 |
| Phase 1-2 要件定義 | dev-flow-requirements | Opus 4.7 |
| Phase 3-4 ドキュメント生成 | dev-flow-spec | Haiku 4.5（子: Sonnet） |
| Phase 4.5 整合性チェック | dev-flow-consistency | Haiku 4.5（子: Opus） |
| Phase 5 実装 | dev-flow-implementation | Haiku 4.5（子: Sonnet） |
| Phase 6 テスト | dev-flow-test | Haiku → Sonnet（自動昇格） |
| Phase 7-8 準拠チェック | dev-flow-compliance | Opus 4.7 |

---

## トラブルシューティング

**最初からやり直す**

```bash
rm doc/process/state.json
/dev-flow
```

**特定フェーズからやり直す**

```bash
rm doc/process/state.json
/dev-flow --from=spec
```

**状態ファイルの場所**

```
{プロジェクトルート}/doc/process/state.json
```
