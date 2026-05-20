# dev-flow スキル集

Claude Code 用の AI 駆動開発フロースキルです。要件定義から実装・テスト・完了確認まで、一貫した開発フローを自動化します。

---

## 設計思想

### DocDD（ドキュメント駆動開発）

このフローは **DocDD（Document-Driven Development）** の思想に基づいています。

**ドキュメントが唯一の正解であり、実装はドキュメントに従う。**

| フェーズ | DocDD における役割 |
|---|---|
| Phase 1-2 要件定義 | 実装の前に要件を文書化し、人間のレビューで凍結する |
| Phase 3-4 ドキュメント生成 | 要件定義書からテスト定義書・API仕様書・インフラ仕様書・UIモックを先行生成する |
| Phase 4.5 整合性チェック | ドキュメント間の矛盾を実装前に解消し、設計を凍結する |
| Phase 5 実装 | 凍結されたドキュメントに従って実装する（ドキュメントの変更は不可） |
| Phase 7-8 準拠チェック | 実装がドキュメントに完全に準拠しているかを検証する。乖離があれば**実装側を修正する**（ドキュメントは変更しない） |

コードよりドキュメントが先に存在することで、「何を作るか」の認識齟齬を実装前に解消できます。

### ハーネスエンジニアリング

Claude Code のハーネス機能を最大限に活用して、マルチエージェント並列実行と自動エスカレーションを実現しています。

**並列ドキュメント生成（Phase 3-4）**

```
TeamCreate("doc-team")
    ├── test-spec-writer   (Sonnet) ─── テスト定義書を生成
    ├── api-spec-writer    (Sonnet) ─── API仕様書を生成        } 並列実行
    ├── mock-writer        (Sonnet) ─── UIモックを生成
    └── doc-orchestrator   (Haiku)  ─── 完了通知を集約して報告
```

**DAGベース並列実装（Phase 5）**

```
git worktree でブランチを分離 + DAG依存解決
    ├── グループ 1 (Infra) — depends_on: []  → 即時実行
    │   ├── dev/infra-group-1 (Haiku→Sonnet) ─── Infra Dev タスク
    │   └── qa/infra-group-1  (Haiku→Sonnet) ─── Infra QA タスク  } 並列
    │
    ├── グループ 2 (App) — depends_on: []    → 即時実行
    │   ├── dev/app-group-2   (Haiku→Sonnet) ─── App Dev タスク
    │   └── qa/app-group-2    (Haiku→Sonnet) ─── App QA タスク    } 並列
    │
    └── グループ 3 (Cross) — depends_on: [group-1]  → group-1 完了後に実行
        ├── dev/infra-group-3 (Haiku→Sonnet) ─── Infra Dev タスク
        ├── qa/infra-group-3  (Haiku→Sonnet) ─── Infra QA タスク  } 順次
        ├── dev/app-group-3   (Haiku→Sonnet) ─── App Dev タスク
        └── qa/app-group-3    (Haiku→Sonnet) ─── App QA タスク

完了したグループから順次マージ
```

**自動モデル昇格（実装・レビュー）**

```
初回実装: Haiku（最大2回修正）
    ├── 通過 → レビューへ
    └── 設計レベルの指摘 → Sonnet に昇格（最大3回）
                              └── 解決不能 → 人間にエスカレーション
```

**セッションをまたぐ状態管理**

各フェーズの完了時に `doc/process/state.json` へ状態を保存。次回の `/dev-flow` 実行時に自動復元するため、会話が途切れても中断したフェーズから継続できます。`harness` セクションに再現性メタデータ（フェーズ履歴・深度制限）を記録し、無限ループを防止します。

**サブスキル分割によるコンテキスト最適化**

メインオーケストレーター（`dev-flow/SKILL.md`）は軽量に保ち、各フェーズの詳細定義は `dev-flow/phase-*.md` にサブスキルとして分離しています。`current_phase` に応じて必要なサブスキルだけを読み込むことで、読み込み負荷を大幅に削減し、`/dev-flow:phase-test` のように個別フェーズを直接実行することもできます。

---

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
│  - 曖昧表現リント・用語集（_glossary.md）の整備         │
│  - 要件定義書を doc/requirements/ に生成                │
│  - トレーサビリティID（REQ-NNN）を frontmatter に付与   │
│                               モデル: Opus 4.7           │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 3-4: ドキュメント生成  (/dev-flow-spec)          │
│  - テスト定義書・API仕様書・インフラ仕様書・UIモック    │
│    を並列生成                                           │
│  - frontmatter に covers: [REQ-NNN] を記録              │
│  - OpenAPI 3.1.0 / Gherkin 形式で機械可読化             │
│  - doc/test-spec/, doc/api-spec/, doc/infra-spec/,      │
│    doc/mock/ に出力                                     │
│                               モデル: Haiku (子: Sonnet) │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 4.4: Impact Analysis（incremental mode のみ）    │
│  - baseline_commit 以降のドキュメント変更を分析         │
│  - 影響を受ける REQ-ID / TC-ID / API-ID を特定          │
│  - 影響範囲のタスクのみチェックリスト化                 │
│                               モデル: Sonnet             │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 4.5: 整合性チェック  (/dev-flow-consistency)     │
│  - Phase 4.5a-pre: トレーサビリティID整合性チェック     │
│    （存在しないREQ-IDへの参照を検出）                   │
│  - Phase 4.5a: ドキュメント間の矛盾・考慮漏れを検出    │
│  - Phase 4.5a-post: カバレッジ行列を生成                │
│    （coverage_matrix.md: REQ × TC × API のマッピング）  │
│  - Phase 4.5b: タスクを Infra/App/Cross に分類          │
│    （depends_on DAG でグループ間依存を定義）            │
│  - タスク分解・設計凍結コミット                         │
│                               モデル: Haiku (子: Opus)   │
└───────────────────────┬─────────────────────────────────┘
                        │ /dev-flow
                        ▼
┌─────────────────────────────────────────────────────────┐
│  Phase 5: 並列実装  (/dev-flow-implementation)          │
│  - DAG依存を解決しながらグループを並列実行              │
│  - 過去のレビュー指摘パターンをプロンプトに注入         │
│  - ファイルスコープガードレールでチーム間干渉を防止     │
│  - Implements:/Tests: コミットフッターでトレーサビリティ │
│  - 推論トレースを doc/process/reasoning/ に記録         │
│  - Plan Repair フロー（計画誤りを動的修正）             │
│  - レビュアーエージェントで独立コードレビュー           │
│                               モデル: Haiku → Sonnet     │
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
│  - Phase 7-pre: カバレッジ行列で機械的検証              │
│    （TC-NNN・API-NNN の実装存在確認）                   │
│  - Phase 7: 実装がドキュメントに準拠しているか確認      │
│  - 完了報告を生成                                       │
│                               モデル: Opus 4.7           │
└─────────────────────────────────────────────────────────┘
```

---

## 主要機能

### トレーサビリティID体系

ドキュメント間の整合性を ID で管理します。

| 種別 | フォーマット | 例 | 用途 |
|---|---|---|---|
| 要件 | `REQ-NNN` | `REQ-001` | 要件定義書の frontmatter |
| テストケース | `TC-NNN` | `TC-001` | テスト定義書の frontmatter |
| API エンドポイント | `API-NNN` | `API-001` | API 仕様書の frontmatter |
| インフラリソース | `INFRA-NNN` | `INFRA-001` | インフラ仕様書の frontmatter |

テスト定義書・API仕様書の frontmatter に `covers: [REQ-NNN]` を記載することで、どの要件がどのドキュメントでカバーされているかを機械的に追跡できます。コミットメッセージにも `Implements: REQ-001, API-001` / `Tests: TC-001, TC-002` フッターを付与して、コード変更との紐付けを維持します。

### カバレッジ行列

Phase 4.5a-post で `doc/process/coverage_matrix.md` を自動生成します。

```markdown
| 要件ID | 要件タイトル | テストID | API/エンドポイント | 実装タスク |
|---|---|---|---|---|
| REQ-001 | ユーザー認証 | TC-001, TC-002 | API-001 (POST /auth/login) | （チェックリスト生成後に補完） |
| REQ-003 | ログアウト | ❌ 未カバー | ❌ | ❌ |
```

未カバー要件が検出された場合は人間に判断を求め、Phase 3 に戻るかテスト追加・除外範囲として記録するかを選択できます。Phase 7-pre では、この行列を使って TC-NNN の実装存在・API-NNN のルート定義を機械的に検証します。

### Plan Repair フロー

Phase 5 実装中に実装エージェントが「計画誤り」を検出した場合（依存関係の発見・グループ分けの誤り等）、`plan_repair_needed` ブロッカーを返します。オーケストレーターは人間に修正方針を確認してから Phase 4.5 を mini モードで再実行し、未着手グループのみチェックリストを更新します。同一フロー内で最大3回まで自動修正し、上限到達後は人間にエスカレーションします。

### 構造化通知スキーマ

実装・QA エージェントは以下の JSON で完了・ブロッカーを報告します。

```json
{
  "agent": "dev-implementer-app-group-1",
  "status": "completed",
  "result": { "changed_files": 5, "commits": ["abc1234"] },
  "confidence": 0.85,
  "uncertainty_points": [
    {
      "topic": "キャッシュの無効化タイミング",
      "reason": "要件に明示なし",
      "alternatives_considered": ["書き込み時", "TTL切れ時"],
      "chosen": "書き込み時",
      "rationale": "一貫性を優先"
    }
  ],
  "needs_human_review": false,
  "blockers": []
}
```

`uncertainty_points` が1件以上ある場合は `needs_human_review: true` とし、レビュー時に人間が確認します。

### レビュアー独立性

レビュアーエージェントは `disallowed_tools: ["Edit", "Write", "NotebookEdit"]` で起動するため、実装コードを直接書き換えることができません。指摘のみを行い、修正は実装エージェントが担当します。観点は以下の通りです：

- **Dev レビュアー（懐疑的観点）**: セキュリティホール・新人可読性・アーキテクチャ
- **QA レビュアー（素朴質問観点）**: 理解できない点・テストの意図が不明な点のみ指摘

### memory注入

過去のレビューで3回以上繰り返された指摘パターンや、人間によるマージ後修正を Claude memory に保存します。次回フロー実行時、エージェント起動前にそのパターンをプロンプトに注入することで、同じ指摘の再発を防ぎます。

### 機械可読フォーマット

| ドキュメント種別 | フォーマット |
|---|---|
| API 仕様書 | OpenAPI 3.1.0（`x-req-id` / `x-api-id` vendor extension で REQ/API ID を付与） |
| テスト定義書 | Gherkin Given-When-Then 形式 |
| 要件定義書 | 曖昧表現リント済み + `_glossary.md` に専門用語を定義 |

---

## チーム分離アーキテクチャ

Phase 4.5 でタスクを影響範囲に基づいて自動分類し、Phase 5 で必要なチームのみ起動することで、不要なエージェント実行を防ぎます。

### タスク分類ルール

| チーム種別 | 判定基準 | 例 |
|---|---|---|
| **Infra** | インフラのみ変更 | EC2 インスタンスタイプ変更、S3 バケット追加 |
| **App** | アプリのみ変更 | API エンドポイント追加、UI コンポーネント変更 |
| **Cross** | インフラとアプリ両方に影響 | 環境変数追加、新規データベース追加 |

### DAG依存実行

チェックリストの各グループに `depends_on` フィールドを設定することで、グループ間の依存関係を宣言的に管理します。

```
### グループ 1 (Infra) — depends_on: []
### グループ 2 (App) — depends_on: []
### グループ 3 (Cross) — depends_on: [group-1]
```

`depends_on` が空のグループは即時並列実行、依存先が完了したグループは順次解放されます。

### 実行パターン

**Infra グループ**: Infra Dev/QA のみ起動（アプリチームは起動しない）

**App グループ**: App Dev/QA のみ起動（インフラチームは起動しない）

**Cross グループ**: Infra Dev → Infra QA → App Dev → App QA を順次起動

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

### 開発モード

| モード | 用途 | 指定方法 |
|---|---|---|
| `full`（デフォルト） | 新規開発（全フェーズ実行） | `/dev-flow 新機能を追加` |
| `incremental` | 要件追加（差分のみ実装） | `/dev-flow` 実行時にモード選択 |

`incremental` モードでは Phase 4.4 で baseline_commit 以降の変更を分析し、影響範囲のタスクのみを実装します。

### プロジェクトタイプ指定

```
/dev-flow API を実装 --no-gui   # API プロジェクト（UIモック不要）
/dev-flow 画面を実装 --no-api   # GUI プロジェクト（API仕様書不要）
```

---

## スキル構成

```
dev-flow-skills/
├── dev-flow/                       # メインオーケストレーター（サブスキル方式）
│   ├── SKILL.md                    # 軽量エントリポイント・状態管理・サブスキル呼び出し
│   ├── README.md                   # サブスキル構成・モデル構成・コスト最適化の解説
│   ├── phase-requirements.md       # Phase 1-2 詳細（Opus）
│   ├── phase-spec.md               # Phase 3-4 詳細（Haiku）
│   ├── phase-consistency.md        # Phase 4.5 詳細（Haiku）
│   ├── phase-implementation.md     # Phase 5 詳細（Haiku）
│   ├── phase-test.md               # Phase 6 詳細（Haiku → Sonnet）
│   └── phase-compliance.md         # Phase 7-8 詳細（Opus）
├── dev-flow-requirements/          # Phase 1-2 スキル
│   └── SKILL.md                    # 要件定義・曖昧表現リント・用語集生成
├── dev-flow-spec/                  # Phase 3-4 スキル
│   ├── SKILL.md                    # ドキュメント並列生成オーケストレーター
│   └── prompts/
│       ├── test-spec-writer.md     # テスト定義書（Gherkin形式）
│       ├── test-spec-reviewer.md   # テスト定義書レビュー
│       ├── api-spec-writer.md      # API仕様書（OpenAPI 3.1.0）
│       ├── api-spec-reviewer.md    # API仕様書レビュー
│       ├── infra-spec-writer.md    # インフラ仕様書
│       ├── infra-spec-reviewer.md  # インフラ仕様書レビュー
│       ├── mock-writer.md          # UIモック（HTML）
│       ├── mock-reviewer.md        # UIモックレビュー
│       └── doc-orchestrator.md     # 完了通知集約
├── dev-flow-consistency/           # Phase 4.5 スキル
│   ├── SKILL.md                    # ID整合性・カバレッジ行列・Impact Analysis
│   └── prompts/
│       ├── consistency-check.md    # ドキュメント整合性チェック
│       ├── checklist-writer.md     # タスクチェックリスト（DAG依存付き）
│       └── spec-cache-writer.md    # スペックキャッシュ生成
├── dev-flow-implementation/        # Phase 5 スキル
│   ├── SKILL.md                    # 実装オーケストレーター・Plan Repair
│   └── prompts/                    # エージェントプロンプト（チーム別）
│       ├── dev-infra.md            # Infra Dev（推論トレース・JSON通知）
│       ├── dev-app.md              # App Dev（推論トレース・JSON通知）
│       ├── qa-infra.md             # Infra QA（JSON通知）
│       └── qa-app.md               # App QA（JSON通知）
├── dev-flow-test/                  # Phase 6 スキル
│   └── SKILL.md                    # テスト実行・モデル昇格
├── dev-flow-compliance/            # Phase 7-8 スキル
│   └── SKILL.md                    # カバレッジ行列検証・準拠チェック
└── setup.sh                        # シンボリックリンク作成スクリプト
```

---

## モデル構成

| フェーズ | スキル | モデル |
|---|---|---|
| オーケストレーター | dev-flow | Haiku 4.5 |
| Phase 1-2 要件定義 | dev-flow-requirements | Opus 4.7 |
| Phase 3-4 ドキュメント生成 | dev-flow-spec | Haiku 4.5（子: Sonnet） |
| Phase 4.4 Impact Analysis | dev-flow-consistency | Sonnet |
| Phase 4.5 整合性チェック | dev-flow-consistency | Haiku 4.5（整合性チェック子: Opus） |
| Phase 5 実装 | dev-flow-implementation | Haiku → Sonnet（自動昇格） |
| Phase 5 レビュー | dev-flow-implementation | Haiku → Sonnet（disallowed_tools付き） |
| Phase 6 テスト | dev-flow-test | Haiku → Sonnet（自動昇格） |
| Phase 7-8 準拠チェック | dev-flow-compliance | Opus 4.7 |

---

## 生成物一覧

フロー完了後に以下のファイルが生成されます。

```
{プロジェクトルート}/
├── doc/
│   ├── requirements/
│   │   ├── *.md                    # 要件定義書（REQ-NNN ID付き）
│   │   └── _glossary.md            # 用語集
│   ├── test-spec/                  # テスト定義書（TC-NNN・Gherkin形式）
│   ├── api-spec/                   # API仕様書（API-NNN・OpenAPI 3.1.0）
│   ├── infra-spec/                 # インフラ仕様書（INFRA-NNN）
│   ├── mock/                       # UIモック（*.html）
│   └── internal/
│       └── spec_cache.md           # スペックキャッシュ（実装エージェント向け）
└── doc/process/
    ├── state.json                  # フロー状態（セッション再開用）
    ├── task_checklist.md           # タスクチェックリスト（DAG依存付き）
    ├── coverage_matrix.md          # カバレッジ行列（REQ × TC × API）
    ├── plan_repair_log.md          # Plan Repair 履歴
    ├── reasoning/
    │   └── phase5-*.md             # 実装エージェントの推論トレース
    └── escalation_*.md             # エスカレーション報告（発生時のみ）
```

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

**Plan Repair が繰り返し発動する**

`doc/process/plan_repair_log.md` を確認して、根本的なタスク分類の誤りがないかを検討してください。3回上限に達した場合は人間がタスクチェックリストを直接修正して `/dev-flow` を再実行します。

**状態ファイルの場所**

```
{プロジェクトルート}/doc/process/state.json
```
