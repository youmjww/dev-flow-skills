# evals

dev-flow のスキル本体（プロンプト）を測るための評価セット。hooks のテスト（`tests/hooks/`）が「決定的な部品」を検証するのに対し、ここは「LLM が出す成果物」を機械的に採点する。

## 構成

```
evals/
├── fixtures/
│   ├── sample-project/      # 要件定義書・テスト定義書・API 仕様書・チェックリスト・テストコードの揃った最小プロジェクト
│   │                        #   doc-validate のテスト fixture と、writer のお手本（golden）を兼ねる
│   └── change-scenario/     # sample-project の要件定義書に REQ-003 の変更と REQ-006 の追加を加えたもの
├── lib/
│   └── score-test-spec.py   # test-spec-writer の出力を採点（決定的・LLM 不使用）
├── run-spec-eval.sh         # claude -p で writer を実行 → 採点
└── results/                 # 実行ログ（git 管理外）
```

## 実行

```bash
# 決定的な部分だけ（CI 向き・数秒）
bash tests/hooks/run.sh                                   # doc-validate を含む hooks 全部
python3 evals/lib/score-test-spec.py --project-dir evals/fixtures/sample-project --scenario feature

# LLM を回す（1 シナリオ 1〜2 分・数万トークン）
bash evals/run-spec-eval.sh --scenario feature            # 要件定義書から全文生成
bash evals/run-spec-eval.sh --scenario change             # 差分更新: 既存 ID の保持と status マーカー
bash evals/run-spec-eval.sh --scenario all --model haiku --runs 3   # モデル比較・ばらつき確認
```

## 採点項目（`score-test-spec.py`）

`[must]` がすべて PASS で合格。`[nice]` は score にだけ効く。

| チェック | 種別 | 内容 |
|---|---|---|
| output_exists | must | `doc/test-spec/*.md` が生成された |
| schema_valid | must | `doc-validate.py` が通る（hook と同じ検証） |
| req_coverage>=0.8 | must | 要件定義書の REQ の 80% 以上を何らかの TC が covers |
| req_coverage==1.0 | nice | 100% |
| all_tc_have_gherkin | must | 全 TC に ```` ```gherkin ```` ブロック |
| all_tc_have_io_values | must | 全 TC に「入力」「期待出力」 |
| tc_title_prefix | nice | タイトルが `正常系:` 等の接頭辞で始まる |
| no_ambiguous_words | nice | 「適切に」「必要に応じて」「など」等が無い |
| has_normal_and_error_cases | must | 正常系・異常系の両方がある |
| existing_ids_preserved | must（change） | 変更前の TC-ID が 1 つも消えていない |
| untouched_tc_unchanged | must（change） | 変更 REQ と無関係な TC のタイトル・status が不変 |
| modified_tc_marked | must（change） | modified な REQ を covers する既存 TC に `status: modified` |
| added_tc_marked_and_numbered | must（change） | 新 TC が `status: added` かつ既存最大番号 + 1 以降 |
| added_req_covered | must（change） | added な REQ を covers する新 TC がある |

## 実績

| 日付 | シナリオ | モデル | 結果 |
|---|---|---|---|
| 2026-09-21 | feature | sonnet | must 6/6, score 0.89（17 TC, REQ 網羅 100%, 62 秒） |
| 2026-09-21 | change | sonnet | must 11/11, score 0.86（既存 4 TC 保持, +2 TC, 43 秒） |

feature の初回実行でタイトル接頭辞の指示が writer プロンプトに無いことが判明し、プロンプトを修正した（eval がプロンプトの穴を見つけた例）。

## 追加するなら

- `api-spec-writer` / `consistency-check` / `checklist-writer` の採点器（frontmatter と DAG の機械検証で書ける）
- `fix` シナリオ（再現 TC の追加、`covers: []` の報告）
- Haiku での実行結果を蓄積して、各ステージのモデル選定の根拠にする
