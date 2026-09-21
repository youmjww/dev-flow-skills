# テストコード（言語横断）

言語に関係なく**常に**注入する。言語別ファイル（`go.md` 等）の「テスト」節はこのファイルの上に読む。QA implementer / QA reviewer が主な対象だが、`test/branch-coverage` は Dev reviewer にも渡す（実装側が増やした分岐に TC を要求するため）。

## 書き方（QA implementer 向け）

### 何をテストするか
- **テスト定義書の TC を 1 つずつ実装する**。TC-ID をテスト名またはコメントに書く（`// TC-003`）。compliance がこれで対応を検証する
- **正常系だけで終わらない**。公開関数・エンドポイントごとに、少なくとも 1 つの異常系（不正入力・権限なし・存在しないリソース・依存先の失敗）を書く。テスト定義書に異常系の TC が無ければ、**テストを省略せずテスト定義書に TC を追加する**（`status: added`）
- **分岐ごとに 1 ケース**。実装コードの `if` / `switch` / 早期 `return` / `catch` / 三項演算子を数え、それぞれを通るケースがあるか確認する。分岐に対応する TC が無ければ追加する。境界値（0・1・上限・上限+1・空・null）は分岐の一種として扱う
- 例外・エラーの**種類**まで検証する（「エラーになる」ではなく「`ErrNotFound` / HTTP 404 / `ValidationError` になる」）
- 副作用を検証する（DB に行が入った・メールが送られた・イベントが発火した）。戻り値だけ見て終わらない

### どう書くか
- **1 テスト 1 振る舞い**。1 つのテストで 5 個の assert を並べるなら、5 つの振る舞いを混ぜていないか疑う
- テストは**独立**。実行順序・他テストの残した状態・共有のグローバルに依存しない。並列実行しても通る
- **決定的**。`time.Now()` / 乱数 / ネットワーク / 環境変数に依存しない。時計は注入、外部は境界でフェイク
- モックするのは**境界だけ**（HTTP・DB・時計・メール・キュー）。テスト対象自身やその内部関数をモックしたら、それはテストではない
- 期待値は**リテラルで書く**。実装と同じ計算式で期待値を作ると常に通る（`expected := calc(x); assert(calc(x) == expected)`）
- テスト名は「条件 → 期待結果」が読める形（`TestLogin_WrongPassword_Returns401`、`it("returns 401 when password is wrong")`）。`test1` / `testCase` 禁止
- スナップショットテストは UI の構造確認にだけ使い、ロジックの検証に使わない

### やってはいけないこと
- **テストを消さない・スキップしない・コメントアウトしない**。通らないなら、プロダクションコードを直すか、テスト定義書の誤りとしてエスカレーションする。`t.Skip` / `it.skip` / `@pytest.mark.skip` / `markTestSkipped` は PR マージ時に hook が検出して止める
- **期待値を実行結果に合わせて書き換えない**。テストは仕様（テスト定義書）から書く。実装を動かして出た値を貼るのは「テスト」ではなく「記録」
- `assert true` / assert の無いテスト / `try { ... } catch {}` で例外を握りつぶすテストを書かない
- `sleep` でタイミングを合わせない。非同期は完了を待つ仕組み（`waitFor` / channel / `Eventually`）で

## レビューチェックリスト（QA reviewer 向け。`test/branch-coverage` は Dev reviewer も）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `test/no-delete` | blocker | 既存テストが削除・コメントアウトされていない（移動は可） | `git diff --diff-filter=D`、削除行の `func Test` / `def test_` / `it(` |
| `test/no-skip` | blocker | スキップ・無効化が追加されていない | `grep -nE 't\.Skip\(|\.skip\(|mark\.skip|markTestSkipped|xit\('` |
| `test/expected-from-impl` | blocker | 期待値が実装の出力を貼ったものでない（テスト定義書の値と一致） | テスト定義書の「具体的な入出力値」と突き合わせ |
| `test/error-cases` | major | 変更した公開関数・エンドポイントごとに異常系が 1 つ以上ある | 関数ごとに正常系 / 異常系のテスト数を数える |
| `test/branch-coverage` | major | 変更した関数の `if` / `switch` / 早期 return / `catch` それぞれを通るケースがある | 分岐を列挙して対応テストを探す。カバレッジレポートがあれば分岐カバレッジの未到達行 |
| `test/assert-present` | major | すべてのテストに意味のある assert がある | assert の無いテスト関数、`assert true` |
| `test/no-sut-mock` | major | テスト対象自身・同一モジュールの内部関数をモックしていない | モック対象がインターフェース境界か |
| `test/tautology` | major | 期待値を実装と同じロジックで計算していない | `expected := f(x)` の形 |
| `test/independent` | major | 順序依存・共有可変状態・グローバルに依存していない | 単体で実行して通るか、並列実行フラグ |
| `test/deterministic` | major | 時刻・乱数・実ネットワーク・`sleep` に依存していない | `time.Now` / `Math.random` / `sleep` / 実 URL |
| `test/error-type` | major | 異常系が「エラーになる」ではなくエラーの種類・コードを検証している | `assert.Error` だけで終わっていないか |
| `test/side-effects` | minor | 副作用（DB・通知・イベント）が検証されている | 変更系の処理に `assertDatabaseHas` 相当 |
| `test/tc-id` | minor | テストに TC-ID が対応付けられている | `grep -c 'TC-[0-9]'` |
| `test/naming` | minor | テスト名から条件と期待結果が読める | 目視 |
| `test/one-behavior` | minor | 1 テストに複数の振る舞いを詰めていない | assert の数と対象 |

## 標準コマンド（分岐カバレッジ）

QA implementer は完了 JSON の `result.coverage` に**分岐カバレッジ**（無ければ行カバレッジ）を書く。閾値は `doc/conventions.md` の `coverage_threshold`（既定 **0.80**）。**変更した関数**の分岐カバレッジが閾値未満ならレビューに進まない（lint と同じゲート）。既存コード全体の数字ではなく、`git diff` で変更した関数に絞って見る。

| 言語 | コマンド | 備考 |
|---|---|---|
| Go | `go test -coverprofile=cover.out ./... && go tool cover -func=cover.out` | Go は行（ステートメント）カバレッジのみ。分岐は reviewer が目視 |
| Python | `pytest --cov=src --cov-branch --cov-report=term-missing` | `--cov-branch` で分岐 |
| TypeScript | `vitest run --coverage`（`@vitest/coverage-v8`）/ `jest --coverage` | レポートの `Branch` 列 |
| PHP | `./vendor/bin/phpunit --coverage-text`（Xdebug / PCOV 必要）/ `php artisan test --coverage` | 行のみ |

完了 JSON の例：

```json
"result": {
  "lint": {"command": "...", "exit_code": 0},
  "coverage": {"kind": "branch", "value": 0.87, "changed_functions_below_threshold": []}
}
```

`changed_functions_below_threshold` が空でなければ、その関数の未到達分岐に対応する TC をテスト定義書に追加して実装する（テストを減らして数字を上げる方向は禁止）。

## 出典と対象バージョン

| 項目 | 出典 | 備考 |
|---|---|---|
| verified_against | 言語非依存 | ツール固有の項目は各言語ファイルの出典を参照 |
| 境界をモックし SUT をモックしない・独立・決定的 | https://martinfowler.com/articles/mocksArentStubs.html 、https://testing.googleblog.com/2016/05/testing-on-toilet-change-detector-tests.html | `[opinion]` 寄りだが広く合意 |
| 分岐ごとのテスト（分岐網羅） | https://en.wikipedia.org/wiki/Code_coverage#Basic_coverage_criteria | 分岐網羅は業界標準の用語 |
| 期待値を実装から作らない（tautological test） | https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html | |
| テストを消す・スキップするのは最終手段 | — | DocDD の「ドキュメントが正解・コードを直す」から導かれる本フロー固有のルール |
| `sleep` ではなく完了待ち | https://testing-library.com/docs/dom-testing-library/api-async/ 、https://pkg.go.dev/github.com/stretchr/testify/assert#Eventually | |
| カバレッジ閾値 80% | — | `[opinion]`。`doc/conventions.md` の `coverage_threshold` で変更 |
