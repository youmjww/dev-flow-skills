# PHP

Laravel の土台。`laravel.md` はこのファイルの上に読む。

## 書き方（implementer 向け）

### 命名・構成
- PSR-12（コーディングスタイル）と PSR-4（オートロード）に従う。クラスは `PascalCase`、メソッド・変数は `camelCase`、定数は `UPPER_SNAKE`
- すべてのファイルの先頭に `declare(strict_types=1);`
- 引数・戻り値・プロパティに**型を必ず宣言**する。`mixed` は理由がある場合のみ。nullable は `?Type`、union は最小限
- `readonly` プロパティ・コンストラクタプロモーション（`public function __construct(private readonly Foo $foo)`）を使う
- `enum`（PHP 8.1+）を文字列定数の代わりに使う。backed enum で永続化
- グローバル関数・静的ユーティリティクラス（`Helper::`）を増やさない。依存はコンストラクタで注入

### エラー処理
- 例外を使う。エラーを `false` / `null` / `-1` の戻り値で表現しない
- 捕まえる例外を特定する。`catch (\Throwable $e)` は最上位（ハンドラ）だけ。握りつぶし（`catch (\Exception $e) {}`）禁止
- 再送出は `throw new AppException("...", previous: $e)` で原因を保つ
- `@` 演算子でエラーを抑制しない

### 並行処理・非同期
- PHP は基本同期。時間のかかる処理（メール・外部 API・集計）はキュー（ジョブ）に逃がす
- ジョブは冪等に書く（リトライで二重実行される前提）

### 依存・境界
- 外部 I/O（DB・HTTP・時計・乱数）はインターフェース越しに注入し、テストで差し替える。`new DateTime()` / `time()` を直接呼ばない
- Composer の依存はバージョンを固定（`composer.lock` をコミット）
- `$_GET` / `$_POST` / `$_SERVER` を直接読まない（フレームワークの Request を経由）

### テスト
- PHPUnit（または Pest）。テスト名は `test_login_with_wrong_password_returns_401` か Pest の `it("returns 401 when password is wrong")`。TC-ID をコメントで対応付ける
- 複数ケースは `#[DataProvider]`（PHPUnit）/ `->with([...])`（Pest）
- モックは境界（HTTP・時計・外部サービス）だけ。自クラスの内部を `Mockery::mock` し始めたら設計を疑う

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `php/sql-injection` | blocker | SQL を文字列結合で組み立てていない（プレースホルダ / クエリビルダ） | `grep -nE '(->raw\(|DB::raw\(|whereRaw\().*\$'`、`"SELECT.*\$` |
| `php/xss` | blocker | エスケープなしの出力（`{!! !!}`、`echo $input`）に外部入力を渡していない | `grep -n '{!!'`、`echo \$` |
| `php/secrets-hardcoded` | blocker | トークン・鍵がソースに無い（`.env` 経由） | `grep -niE '(password|secret|token|api_key)\s*=>?\s*["\x27][^"\x27]+'` |
| `php/authz-missing` | blocker | 認可が必要な処理で権限チェックが抜けていない | ルート / コントローラごとに要件定義書と照合 |
| `php/unserialize-input` | blocker | 外部入力を `unserialize` / `eval` していない | `grep -nE '\b(unserialize|eval)\('` |
| `php/strict-types` | major | 全ファイルに `declare(strict_types=1)` | `grep -L 'strict_types=1' **/*.php` |
| `php/missing-types` | major | 引数・戻り値の型宣言が揃っている | `phpstan` level 6 以上 |
| `php/exception-swallowed` | major | 空の `catch` / `catch (\Throwable)` が最上位以外に無い | `grep -nE 'catch \(\\\\?(Exception|Throwable)'` |
| `php/error-suppress` | major | `@` 演算子を使っていない | `grep -nE '[^a-zA-Z_]@\$?[a-z_]+\('` |
| `php/superglobal` | major | `$_GET` / `$_POST` / `$_REQUEST` を直接読んでいない | `grep -nE '\$_(GET|POST|REQUEST|SERVER)'` |
| `php/return-false-as-error` | major | エラーを `false` / `null` で表現していない | 呼び出し側の `=== false` 分岐 |
| `php/time-direct` | major | ビジネスロジックが `new DateTime()` / `time()` / `date()` を直接呼んでいない | `grep -nE 'new DateTime\(|\btime\(\)|\bdate\('` |
| `php/enum` | minor | 文字列定数の集合が `enum` | `const .* = '` の並び |
| `php/data-provider` | minor | 複数ケースが DataProvider | テストの構造 |
| `php/psr12` | minor | `php-cs-fixer` / `pint` が通る | 実行して確認 |

## 標準コマンド（tech_stack が空のときのフォールバック）

| 用途 | コマンド |
|---|---|
| format | `php-cs-fixer fix --dry-run --diff`（Laravel は `pint --test`） |
| lint | `phpstan analyse`（`larastan` 込み、level 6 以上） |
| 型検査 | 同上（PHPStan が担う） |
| test | `phpunit`（または `pest`） |

## 出典と対象バージョン

このファイルは執筆時点（2026-09）の知識で書かれている。`verified_against` より新しい / 古いバージョンでは [version-check.md](version-check.md) の手順で公式ドキュメントと照合し、差分は `doc/process/conventions_verified.md` が優先する。`[version-sensitive]` は変わりやすい項目、`[opinion]` は公式ではなくコミュニティの多数派・筆者の推奨で、`doc/conventions.md` で上書きしてよい。

| 項目 | 出典 | 備考 |
|---|---|---|
| verified_against | PHP 8.3 | 8.4 のプロパティフック・非対称可視性は未記載 `[version-sensitive]` |
| PSR-12 / PSR-4 | https://www.php-fig.org/psr/psr-12/ 、https://www.php-fig.org/psr/psr-4/ | PER Coding Style 2.0（https://www.php-fig.org/per/coding-style/）が PSR-12 の後継 |
| `declare(strict_types=1)` | https://www.php.net/manual/en/language.types.declarations.php#language.types.declarations.strict | |
| コンストラクタプロモーション・`readonly` | https://www.php.net/manual/en/language.oop5.decon.php#language.oop5.decon.constructor.promotion 、https://www.php.net/manual/en/language.oop5.properties.php#language.oop5.properties.readonly-properties | 8.0 / 8.1+ |
| `enum` | https://www.php.net/manual/en/language.enumerations.php | 8.1+ |
| 例外の `previous` | https://www.php.net/manual/en/exception.construct.php | |
| `unserialize` の危険性 | https://www.php.net/manual/en/function.unserialize.php | |
| PHPStan level | https://phpstan.org/user-guide/rule-levels | level 6 は `[opinion]` |
| PHPUnit `DataProvider` / Pest | https://docs.phpunit.de/ 、https://pestphp.com/docs | |
| リリースノート（照合用） | https://www.php.net/releases/{version}/en.php | `{version}` は `8.4` 形式 |
