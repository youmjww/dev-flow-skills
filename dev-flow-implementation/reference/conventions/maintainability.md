# 保守性（言語横断）

言語に関係なく**常に**注入する（`testing.md` と同じ扱い）。Dev implementer と Dev reviewer に渡す。言語別ファイルの規約と矛盾する場合は言語別ファイルを優先する。

## 書き方（implementer 向け）

### 書く前に探す（車輪の再発明をしない）
- 新しい関数・クラス・ヘルパーを書く前に、**同じことをするものが既にないか探す**。順番は ① プロジェクト内の既存コード（`grep -rn` で関数名・処理の特徴的なキーワード・似た定数を検索）→ ② フレームワークの機能 → ③ 言語の標準ライブラリ → ④ 既に入っている依存パッケージ
- 日付・時刻の計算、バリデーション、エスケープ・サニタイズ、パス操作、CSV / JSON / YAML の読み書き、リトライ、並行数の制御、認証・セッション、暗号・ハッシュは**自作しない**。自作が必要な理由があれば完了 JSON の `uncertainty_points` に書く
- 新しい依存パッケージを足す前に、既存の依存と標準ライブラリで賄えないか確認する。足すなら理由を PR 説明に書く

### DRY（同じ知識を一箇所に）
- 重複を避けるのは「コードの見た目」ではなく**知識**（業務ルール・バリデーション条件・定数・変換規則・エラーメッセージ）。同じ条件式やリテラルを 2 か所目に書こうとしたら、既存の定義を使うか一箇所に移す
- **認証・認可・入力検証・エスケープのロジックは絶対にコピーしない**。片方だけ直されて穴になる
- ただし偶然似ているだけの処理を無理に共通化しない（誤った抽象化の方が重複より高くつく）。目安は 3 回目で抽出（rule of three）。フラグ引数で分岐させる共通関数ができたら、共通化を疑う
- テストコードは読みやすさを優先し、ある程度の重複を許す（テストの DRY は fixture / ヘルパーに留める）

### ドメインごとの独立
- ディレクトリ・モジュールは**ドメイン（業務の単位）ごと**に分ける。技術レイヤー（controllers / models / services）だけで切らない。プロジェクトに既存の構成があればそれに合わせる
- 他ドメインの**内部**に触れない。他ドメインのテーブルを直接 SELECT / UPDATE しない、内部モデル・private 関数を import しない。そのドメインの公開インターフェース（サービス・API・イベント）を経由する
- モジュール間に**循環依存を作らない**。A → B → A になったら、共通部分を下位モジュールに出すかイベントで逆向きの依存を切る
- `shared/` `common/` `utils/` に置くのはドメイン知識を持たない汎用処理だけ。「注文の合計金額計算」は shared ではなく注文ドメインに置く

### 変更しやすさ
- 意味のある数値・文字列（上限件数・タイムアウト・ステータス名）は名前付き定数か設定にする
- 1 つの関数は 1 つのことをする。「A して B する」関数は分ける

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `maint/duplicated-security-logic` | blocker | 認証・認可・入力検証・エスケープのロジックがコピーされていない | 差分の認可チェック・検証条件を `grep -rn` し、同じ条件がリポジトリ内に複数あれば共通化を要求 |
| `maint/reinvented-wheel` | major | プロジェクト内の既存関数・フレームワーク・標準ライブラリ・既存依存で済む処理を自作していない | 差分で追加した関数ごとに、名前と処理の特徴的なキーワードで `grep -rn` し、フレームワーク・標準ライブラリの該当機能を確認する。**実際に探してから指摘する**（`fix` に使うべき既存の関数・API 名を書く） |
| `maint/duplicated-knowledge` | major | 同じ業務ルール・バリデーション条件・定数・変換規則が複数箇所に書かれていない | 差分で追加した条件式・リテラルを `grep -rn` してリポジトリ内の出現数を数える。2 か所以上なら一箇所に寄せる |
| `maint/domain-boundary` | major | 他ドメインの内部（テーブル・内部モデル・private 関数）に直接触れず、公開インターフェース経由 | 差分の import / use 文と SQL のテーブル名を見て、所属ドメイン外のものを列挙する |
| `maint/circular-dependency` | major | モジュール間の循環依存が無い | 差分の import で A → B → A ができていないか。ツールがあれば「標準コマンド」で確認 |
| `maint/shared-domain-leak` | minor | `shared` / `common` / `utils` にドメイン固有の知識を置いていない | 追加先パスと中身 |
| `maint/premature-abstraction` | minor | 1 か所でしか使わない抽象、偶然似ているだけの処理の共通化、フラグ引数で分岐する共通関数を作っていない | 新しい interface / 基底クラス / 共通関数の利用箇所数 |
| `maint/new-dependency` | minor | 新しい依存パッケージに理由がある（既存依存・標準ライブラリで賄えない） | `package.json` / `composer.json` / `go.mod` / `pyproject.toml` の diff と PR 説明 |
| `maint/magic-value` | minor | 意味のある数値・文字列が名前付き定数・設定になっている | 差分のリテラル |

## 標準コマンド（tech_stack が空のときのフォールバック）

どれも任意（入っていなければ reviewer が `grep` で代替する）。

| 用途 | コマンド |
|---|---|
| 重複検出 | `npx jscpd --min-lines 8 --reporters console <src>`（言語非依存） |
| 循環依存（TS/JS） | `npx madge --circular --extensions ts,tsx src` |
| 循環依存（PHP） | `vendor/bin/deptrac analyse`（レイヤー定義がある場合） |
| 循環依存（Go） | コンパイラが import cycle を拒否する（`go build ./...`） |
| 循環依存（Python） | `pylint --disable=all --enable=cyclic-import <pkg>` |

## 出典と対象バージョン

| 項目 | 出典 | 備考 |
|---|---|---|
| verified_against | 言語非依存 | ツールのオプションは各ツールの公式ドキュメントを参照 |
| DRY は「知識の重複」を避ける原則 | https://pragprog.com/titles/tpp20/the-pragmatic-programmer-20th-anniversary-edition/ | 『達人プログラマー』 |
| 3 回目で抽出（rule of three） | https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming) | `[opinion]` |
| 誤った抽象化は重複より高くつく | https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction | `[opinion]` |
| ドメインごとの境界 | https://martinfowler.com/bliki/BoundedContext.html | |
| 循環依存を作らない（非循環依存関係の原則） | https://en.wikipedia.org/wiki/Acyclic_dependencies_principle | |
| jscpd | https://github.com/kucherenko/jscpd | |
| madge | https://github.com/pahen/madge | |
