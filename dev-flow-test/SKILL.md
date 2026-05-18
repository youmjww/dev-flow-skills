---
skill: dev-flow-test
description: テスト実行フェーズ（Phase 6）- Haiku で開始、2回失敗で Sonnet に自動昇格してテストを全通過させる
model: claude-haiku-4-5-20251001
---

# Phase 6: テスト実行（ハイブリッドモデル）

## 入力

状態ファイル `doc/process/state.json` から読み込み：
- tech_stack
- is_e2e

## Phase 6-0. チーム作成

```
TeamCreate(name: "test-team")
```

## Phase 6a: test-orchestrator を同期起動

以下のプロンプトで Agent を起動（`team_name="test-team"`, `name="test-orchestrator"`, `run_in_background=false`, `model="claude-haiku-4-5-20251001"`, `mode="acceptEdits"`）：

---
**test-orchestrator プロンプト**

あなたは test-team のオーケストレーターです。テストランナーを管理してすべてのテストを通過させてください。

技術スタック: `{tech_stack}`
E2E テストあり: `{IS_E2E}`

### STEP 1: test-runner-haiku の起動

以下の設定で `test-runner-haiku` を起動してください（`team_name="test-team"`, `name="test-runner-haiku"`, `run_in_background=true`, `model="claude-haiku-4-5-20251001"`, `mode="acceptEdits"`）：

**test-runner-haiku プロンプト:**

テストを実行し、全テストが通過するまでプロダクションコードを修正してください。

**厳守事項**: テストコードの修正は絶対禁止。プロダクションコードのみ修正すること。

技術スタック: `{tech_stack}`
E2E テストあり: `{IS_E2E}`（true の場合は E2E テストも対象に含める）

**試行上限**: 2回

**ループ: 全テスト通過または試行上限まで繰り返す**

1. ユニットテストを `{tech_stack.test_framework}` で実行し、失敗数を記録する
2. IS_E2E=true の場合は `{tech_stack.e2e_framework}` で E2E テストも実行し、失敗数を合算する
3. 全テスト通過 → `test-orchestrator` に「全テスト通過（Haiku）」と SendMessage して終了
4. 試行回数が2回に達した場合 → 以下のフォーマットで `test-orchestrator` に SendMessage して終了：

```
## Haiku 試行上限到達

### 試行履歴
| 試行 | 失敗数 | 主な失敗テスト | 試みた修正 |
|---|---|---|---|
| 1回目 | X件 | ... | ... |
| 2回目 | Y件 | ... | ... |

### 現在も失敗しているテスト
（テスト名・失敗理由の一覧）
```

5. テストの期待値を正として、プロダクションコードの問題を特定する
6. プロダクションコードを修正する
7. 修正した変更を git commit する（コミットメッセージ例: `fix: {失敗テスト名} を修正`）
8. 試行回数を +1 して 1 に戻る

---

### STEP 2: test-runner-haiku からの通知待ち

`test-runner-haiku` からの SendMessage を受信するまで待機します。

- **「全テスト通過（Haiku）」通知** → STEP 4（完了処理）へ進む
- **「Haiku 試行上限到達」通知** → STEP 3（Sonnet 昇格）へ進む

### STEP 3: Sonnet へ昇格（Haiku が2回失敗した場合のみ実行）

Haiku の試行履歴を受け取った場合のみ、以下の設定で `test-runner-sonnet` を起動（`team_name="test-team"`, `name="test-runner-sonnet"`, `run_in_background=false`, `model="claude-sonnet-4-6"`, `mode="acceptEdits"`）：

**test-runner-sonnet プロンプト:**

【モデル昇格通知】
Haiku が2回試行しましたが全テスト通過に至りませんでした。
以下の履歴を参考に、より高度な分析で問題を解決してください。

### Haiku 試行履歴
{Haiku からの試行履歴をここに挿入}

テストを実行し、全テストが通過するまでプロダクションコードを修正してください。

**厳守事項**: テストコードの修正は絶対禁止。プロダクションコードのみ修正すること。

技術スタック: `{tech_stack}`
E2E テストあり: `{IS_E2E}`（true の場合は E2E テストも対象に含める）

**試行上限**: 3回
**連続無進捗の上限**: 2回（直前2回で失敗数が変化しない場合）

**ループ: 全テスト通過または試行上限まで繰り返す**

1. ユニットテストを `{tech_stack.test_framework}` で実行し、失敗数を記録する
2. IS_E2E=true の場合は `{tech_stack.e2e_framework}` で E2E テストも実行し、失敗数を合算する
3. 全テスト通過 → 「全テスト通過（Sonnet）」を返して終了
4. **上限チェック**:
   - 試行回数が3回に達した場合 → エスカレーション報告
   - 直前2回の失敗数が同じ場合 → エスカレーション報告
5. テストの期待値を正として、プロダクションコードの問題を特定する
6. プロダクションコードを修正する
7. 修正した変更を git commit する（コミットメッセージ例: `fix: {失敗テスト名} を修正`）
8. 試行回数を +1 して 1 に戻る

**エスカレーション時の報告フォーマット:**

```
## テスト実行エスカレーション

### Haiku 試行履歴（1〜2回目）
| 試行 | 失敗数 | 主な失敗テスト | 試みた修正 |
|---|---|---|---|
| 1回目 | X件 | ... | ... |
| 2回目 | Y件 | ... | ... |

### Sonnet 試行履歴（3〜5回目: Haiku 2回 + Sonnet 最大3回）
| 試行 | 失敗数 | 主な失敗テスト | 試みた修正 |
|---|---|---|---|
| 3回目（Sonnet 1回目） | Z件 | ... | ... |
| 4回目（Sonnet 2回目） | ... | ... | ... |
| 5回目（Sonnet 3回目） | ... | ... | ... |

### 現在も失敗しているテスト
（テスト名・失敗理由・試みた修正の一覧）

### エスカレーション理由
（上限到達 / 無進捗のどちらか）

### AIが判断できなかった理由
（設計の矛盾 / 要件の曖昧さ / その他）
```

Sonnet エスカレーション発生時は人間に状況を報告して指示を仰ぐ。

### STEP 4: 完了

テスト全通過を確認したら終了する（このエージェントを終了することで、呼び出し元にテスト完了が伝わる）。

---

## Phase 6b: 出力

test-orchestrator の終了を確認したら（= 上の Agent 呼び出しが返ったら）、以下を実行：

1. `doc/process/state.json` を更新（current_phase を "phase_6" に）
2. 人間に「Phase 6 完了。次は `/dev-flow` を実行して Phase 7 に進んでください」と通知
