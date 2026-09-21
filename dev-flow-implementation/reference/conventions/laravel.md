# Laravel

`php.md` の上に読む。

**バージョンで大きく変わる領域**（必ず version-check で照合）: 11 でアプリケーション骨格が変更（`app/Http/Kernel.php` / `app/Console/Kernel.php` 廃止、ミドルウェア・例外処理は `bootstrap/app.php` に集約、`config/` の多くが省略可能、`routes/api.php` は `install:api` で追加、Policy は自動発見）。10 以前の手順書・スニペットはそのまま使えない。12 は 11 からの破壊的変更が最小、13 は 2026 Q1 リリース。

## 書き方（implementer 向け）

### レイヤと責務
- **Controller は薄く**: リクエスト検証（Form Request）→ サービス / アクション呼び出し → レスポンス整形（Resource）だけ。ビジネスロジック・クエリを書かない
- ビジネスロジックは `app/Actions/` または `app/Services/`（プロジェクトの既存に合わせる）。1 アクション 1 クラス 1 `__invoke` / `handle`
- 入力検証は **Form Request**（`php artisan make:request`）。コントローラ内の `$request->validate()` は小規模でも避け、`authorize()` も Form Request 側に書く
- レスポンスは **API Resource**（`JsonResource`）。Eloquent モデルを `return $user;` でそのまま返さない（隠すべきカラムが漏れる）
- 認可は **Policy**（`php artisan make:policy`）+ `$this->authorize()` / `Gate`。コントローラ内の `if ($user->id !== $post->user_id)` を散らさない

### Eloquent
- **N+1 を作らない**: リレーションを使うクエリは `with()` で eager load。開発環境で `Model::preventLazyLoading()` を有効にする
- `$fillable` を明示（`$guarded = []` 禁止）。Mass assignment の穴を作らない
- 生 SQL（`DB::raw` / `whereRaw`）は理由が要る。使うならバインディング必須
- スコープ（`scopeActive`）でクエリの意図を名前にする。同じ `where` の組み合わせをコピペしない
- 大量データは `chunk` / `lazy` / `cursor`。`->get()` で全件をメモリに載せない
- `Model::find($id)` の `null` を確認するか `findOrFail`。`$model->relation->prop` のチェーンで `null` を踏まない
- 属性のキャスト（`$casts`）で `datetime` / `boolean` / `enum` / `encrypted` を宣言する

### マイグレーション
- 1 マイグレーション 1 目的。**本番で走った後のマイグレーションは編集しない**（新しいものを足す）
- `down()` を書く。書けない（データ破壊）場合は理由をコメント
- 外部キーには `->constrained()` と `onDelete` を明示。インデックスは検索・結合に使うカラムに
- カラム削除・型変更・リネームは破壊的変更。`pr-merge-guard` が自動マージを止めるので、人間レビュー前提で PR の説明に影響範囲を書く

### 非同期・副作用
- メール・通知・外部 API・重い集計は **Job**（`ShouldQueue`）。同期で HTTP レスポンスを待たせない
- Job は冪等に。`$tries` / `$backoff` / `failed()` を定義する
- イベント → リスナーの連鎖は追いにくいので、1 段まで。リスナーも `ShouldQueue` を検討

### 設定・環境
- 11 以降、ミドルウェアの登録・例外ハンドリング・ルートファイルの追加は `bootstrap/app.php` の `Application::configure()` で行う。`app/Http/Kernel.php` を作らない `[version-sensitive]`
- `env()` は `config/*.php` の中でだけ呼ぶ。アプリコードからは `config('services.foo.key')`
- 秘密は `.env`（コミットしない）。`.env.example` は更新する
- `APP_DEBUG=true` を本番に出さない

### テスト
- Feature テスト（HTTP 経由）を主、Unit テストをアクション / サービスに。`RefreshDatabase` で DB を毎回初期化
- テストデータは **Factory**。`DB::table()->insert` で直接作らない
- 認証が絡むテストは `actingAs($user)`。認可の境界（他人のリソースに 403）を必ず 1 本書く
- 外部 API は `Http::fake()`、キューは `Queue::fake()`、メールは `Mail::fake()`。時刻は `Carbon::setTestNow()` / `$this->travel()`
- `assertDatabaseHas` で副作用を検証する

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `laravel/mass-assignment` | blocker | `$guarded = []` が無く、`$fillable` が明示されている | `grep -rn 'guarded = \[\]' app/Models` |
| `laravel/authz-policy` | blocker | 変更系のコントローラ / アクションで Policy または Form Request の `authorize()` が効いている | 各エンドポイントに `authorize` / `can` |
| `laravel/model-in-response` | blocker | Eloquent モデルを Resource を通さず返していない（カラム漏洩） | `return \$` の直後がモデル / コレクション |
| `laravel/raw-binding` | blocker | `DB::raw` / `whereRaw` に変数を直接埋めていない | `grep -nE '(raw|whereRaw)\(.*\$'` |
| `laravel/n-plus-one` | major | ループ内でリレーションアクセスするクエリに `with()` がある | `foreach` 内の `->relation` |
| `laravel/fat-controller` | major | コントローラにビジネスロジック・クエリ組み立てが無い | メソッドが 20 行を超える / `DB::` / `->where` がある |
| `laravel/inline-validate` | major | 検証が Form Request | `grep -n 'validate(' app/Http/Controllers` |
| `laravel/env-outside-config` | major | `env()` が `config/` 以外に無い | `grep -rn 'env(' app/` |
| `laravel/migration-edited` | major | 適用済みマイグレーションが編集されていない | `git diff --name-only` に既存 migration が含まれる |
| `laravel/migration-down` | major | `down()` があるか理由コメント | migration ファイル |
| `laravel/sync-heavy` | major | メール・外部 API・集計が Job に逃がされている | コントローラ / アクション内の `Mail::send` / `Http::` |
| `laravel/job-idempotent` | major | Job が再実行に耐える（重複作成しない） | Job の `handle()` |
| `laravel/test-factory` | minor | テストデータが Factory | `DB::table(...)->insert` in tests |
| `laravel/test-authz` | minor | 他人のリソースへの 403 テストがある | Feature テスト |
| `laravel/casts` | minor | 日時・真偽・enum に `$casts` | Model |

## 標準コマンド

| 用途 | コマンド |
|---|---|
| format | `./vendor/bin/pint --test` |
| lint | `./vendor/bin/phpstan analyse`（larastan） |
| test | `php artisan test`（`--parallel` 可） |
| 破壊的変更の確認 | `php artisan migrate:status` と `git diff --name-only -- database/migrations` |

## 出典と対象バージョン

このファイルは執筆時点（2026-09）の知識で書かれている。`verified_against` より新しい / 古いバージョンでは [version-check.md](version-check.md) の手順で公式ドキュメントと照合し、差分は `doc/process/conventions_verified.md` が優先する。`[version-sensitive]` は変わりやすい項目、`[opinion]` は公式ではなくコミュニティの多数派・筆者の推奨で、`doc/conventions.md` で上書きしてよい。

| 項目 | 出典 | 備考 |
|---|---|---|
| verified_against | Laravel 12.x（2026-09-21、リリースノートのみ） | 最新は 13.x。ドキュメント URL は `https://laravel.com/framework/docs/{version}/{page}`（`{version}` は `12.x` 形式）で全バージョン参照可 `[version-sensitive]` |
| リリースノート・サポート表 | https://laravel.com/framework/docs/{version}/releases | 12: PHP 8.2–8.5、13: PHP 8.3–8.5 |
| アップグレードガイド（照合用） | https://laravel.com/framework/docs/{version}/upgrade | |
| 11 の骨格変更 | https://laravel.com/framework/docs/11.x/releases | `bootstrap/app.php`、Kernel 廃止 |
| Form Request・`authorize()` | https://laravel.com/framework/docs/{version}/validation#form-request-validation | |
| Policy / Gate | https://laravel.com/framework/docs/{version}/authorization | 11+ は自動発見 |
| API Resource | https://laravel.com/framework/docs/{version}/eloquent-resources | |
| Eager loading / `preventLazyLoading` | https://laravel.com/framework/docs/{version}/eloquent-relationships#eager-loading 、https://laravel.com/framework/docs/{version}/eloquent#configuring-eloquent-strictness | |
| Mass assignment / `$fillable` | https://laravel.com/framework/docs/{version}/eloquent#mass-assignment | |
| マイグレーション | https://laravel.com/framework/docs/{version}/migrations | |
| Queue / Job（冪等・リトライ） | https://laravel.com/framework/docs/{version}/queues | |
| テスト（Factory / `actingAs` / fake） | https://laravel.com/framework/docs/{version}/testing 、https://laravel.com/framework/docs/{version}/eloquent-factories 、https://laravel.com/framework/docs/{version}/mocking | |
| Pint / larastan | https://laravel.com/framework/docs/{version}/pint 、https://github.com/larastan/larastan | |
| Controller は薄く・Actions / Services | — | `[opinion]`（公式は構成を規定しない。プロジェクトの既存に合わせる） |
