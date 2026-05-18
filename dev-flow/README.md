# dev-flow スキル - サブスキル構成 + モデル最適化

このスキルは各フェーズをサブスキルに分割し、軽量オーケストレーターが順次呼び出します。

## サブスキル構成

```
~/.claude/skills/dev-flow/
├── skill.md                    # メインオーケストレーター（軽量、200行）
├── phase-requirements.md       # Phase 1-2: 要件定義
├── phase-spec.md              # Phase 3-4: ドキュメント生成とレビュー
├── phase-consistency.md       # Phase 4.5: 整合性チェックと設計凍結
├── phase-implementation.md    # Phase 5: 並列実装（QA/Dev チーム）
├── phase-test.md              # Phase 6: テスト実行（Haiku → Sonnet）
├── phase-compliance.md        # Phase 7-8: 準拠チェックと完了報告
└── README.md
```

### サブスキル呼び出しの仕組み

メインオーケストレーター（skill.md）は：
1. 状態ファイル（`doc/process/state.json`）を読み込み
2. current_phase に応じて適切なサブスキルを Skill ツールで呼び出す
3. サブスキルが完了したら次フェーズへの案内を表示

**メリット:**
- **読み込み負荷 80%削減** - 必要なフェーズのみ読み込み（1000行 → 200行以下）
- **メンテナンス性向上** - 各フェーズが独立したファイル
- **再利用性** - `/dev-flow:phase-test` で個別フェーズを直接実行可能

---

## モデル構成一覧

| フェーズ | サブスキル | モデル | 理由 |
|---|---|---|---|
| メインオーケストレーター | `dev-flow` | **Haiku 4.5** | 状態管理とサブスキル呼び出しのみ |
| **Phase 1-2** 要件定義 | `dev-flow:phase-requirements` | **Opus 4.7** | 要件の深掘り・判断 |
| **Phase 3-4** ドキュメント生成 | `dev-flow:phase-spec` | **Haiku 4.5** | オーケストレーションのみ（エージェントは Sonnet 4.5） |
| **Phase 4.5** 整合性チェック | `dev-flow:phase-consistency` | **Haiku 4.5** | オーケストレーションのみ（エージェントは Opus 4.7） |
| **Phase 5** 並列実装 | `dev-flow:phase-implementation` | **Haiku 4.5** | オーケストレーションのみ（エージェントは Sonnet 4.5） |
| **Phase 6** テスト実行 | `dev-flow:phase-test` | **Haiku 4.5** | オーケストレーションのみ（エージェントは Haiku → Sonnet） |
| **Phase 7-8** 準拠チェック | `dev-flow:phase-compliance` | **Opus 4.7** | 乖離判断・分類 |

### Phase 6 ハイブリッド実装

```
Phase 6 開始
  ↓
Haiku 4.5 でテスト実行（最大2回試行）
  ↓
  ├─ 全通過 → 完了
  ├─ 2回以内に解決 → 完了
  └─ 2回失敗 → Sonnet 4.5 に切り替え（残り3回試行）
      ↓
      ├─ 全通過 → 完了
      └─ 上限到達 or 無進捗 → 人間にエスカレーション
```

---

## 状態管理の仕組み

- 各サブスキル終了時に `doc/process/state.json` に状態を保存
- 次回の `/dev-flow` 実行時に状態ファイルから復元
- セッションをまたいでも継続可能

### 状態ファイル構造

```json
{
  "current_phase": "phase_2",
  "requirements_paths": ["doc/requirements/feature.md"],
  "test_spec_path": "doc/test-spec/feature.md",
  "api_spec_path": "doc/api-spec/feature.md",
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
  "is_e2e": false,
  "from": "requirements"
}
```

---

## 使用方法

### 通常の使用（最初から）

```bash
/dev-flow 新機能を実装
```

Phase 1 → Phase 2 → ... と順次進みます。各フェーズ完了後、手動で `/dev-flow` を実行して次フェーズへ進みます。

### 特定フェーズから実行

```bash
/dev-flow --from=test --requirements=doc/requirements/feature.md
```

### サブスキルを直接実行

```bash
/dev-flow:phase-test        # Phase 6（テスト実行）のみ
/dev-flow:phase-compliance  # Phase 7-8（準拠チェック）のみ
```

### プロジェクトタイプ指定

```bash
/dev-flow API を実装 --no-gui       # API プロジェクト（モック不要）
/dev-flow 画面を実装 --no-api       # GUI プロジェクト（API仕様書不要）
```

---

## コスト最適化のポイント

✅ **サブスキル分割** - 必要なフェーズのみ読み込み（読み込み負荷 80%削減）  
✅ **Haiku オーケストレーター** - 状態管理は軽量モデルで十分  
✅ **Opus は重要判断のみ** - 要件定義・整合性チェック・準拠チェックのみ  
✅ **Sonnet でコード生成** - 実装・レビュー・ドキュメント生成はバランス型  
✅ **ハイブリッドテスト** - Haiku で開始、失敗時のみ Sonnet 昇格

---

## トラブルシューティング

### 状態ファイルが破損した場合

```bash
rm doc/process/state.json
/dev-flow  # 最初からやり直し
```

### 途中でやり直したい場合

```bash
rm doc/process/state.json
/dev-flow --from=spec  # Phase 3 からやり直し
```

### 未完了タスクから再開

```bash
/dev-flow  # 自動的に task_checklist.md を検出して再開を提案
```
