# Go

## 書き方（implementer 向け）

### 命名・構成
- パッケージ名は小文字 1 語・単数形（`user` であって `users` / `userUtils` ではない）。`util` / `common` / `helpers` パッケージを作らない
- エクスポートする識別子には doc コメントを付ける（`// Client は ...` の形式で識別子名から始める）
- `internal/` 配下に外部から参照させないコードを置く。レイヤは `cmd/`（エントリポイント）→ `internal/handler` → `internal/service` → `internal/repository` の依存方向を守り、逆方向に import しない
- 構造体の初期化はフィールド名付き（`User{Name: n}`）。位置指定は使わない
- インターフェースは**使う側**のパッケージで定義し、最小（1〜3 メソッド）にする。実装側で「念のため」定義しない

### エラー処理
- エラーは必ず処理する。`_ = f()` でエラーを捨てない。無視が正当なら理由をコメントに書く
- 上位に返すときは `fmt.Errorf("open config %s: %w", path, err)` で**文脈を足して `%w` で包む**。`%v` で包むと `errors.Is` / `errors.As` が効かなくなる
- センチネルエラー（`var ErrNotFound = errors.New("not found")`）と型付きエラーを使い分け、呼び出し側は `errors.Is` / `errors.As` で判定する。文字列比較しない
- `panic` はプログラム起動時の設定不備などリカバリ不能な場合のみ。リクエスト処理中に `panic` しない
- ログ出力とエラー返却を同じ箇所で両方やらない（二重報告）。ログは最上位（ハンドラ / main）で 1 回

### 並行処理・非同期
- `context.Context` は第一引数 `ctx` で受け渡し、構造体に保持しない。I/O・DB・HTTP 呼び出しには必ず `ctx` を渡す
- goroutine を起動したら終了条件を明確にする（`sync.WaitGroup` / `errgroup.Group` / `ctx.Done()`）。「起動しっぱなし」を作らない
- 共有状態は `sync.Mutex` で守るかチャネルで受け渡す。`go test -race` を通す
- タイムアウトは `context.WithTimeout` で呼び出し側が決める。ライブラリ側で固定値を埋め込まない

### 依存・境界
- 外部 I/O（DB・HTTP・時計・乱数）はインターフェース越しに呼び、テストで差し替えられるようにする。`time.Now()` を直接呼ぶ箇所はテスト不能になる
- `init()` で副作用のある処理（接続・登録）をしない
- グローバル変数で状態を持たない。設定は `main` で組み立てて依存として渡す

### テスト
- **テーブル駆動テスト**を基本形にする。`tests := []struct{ name string; in X; want Y; wantErr error }` + `t.Run(tt.name, ...)`
- テスト名は `TestFunc_Condition` 形式（`TestLogin_WrongPassword`）。テスト定義書の TC-ID をコメントで対応付ける（`// TC-002`）
- `t.Helper()` をヘルパー関数に付ける。`t.Parallel()` は共有状態が無いことを確認してから
- HTTP ハンドラは `net/http/httptest` で、DB は実 DB（testcontainers 等）かインターフェースのフェイクで。`sqlmock` で SQL 文字列を検証するテストは壊れやすいので避ける
- アサーションは標準 `testing` + 必要なら `github.com/google/go-cmp/cmp`。`reflect.DeepEqual` の失敗メッセージは読めないので使わない

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `go/sql-injection` | blocker | SQL を文字列結合・`fmt.Sprintf` で組み立てていない | `grep -nE 'Sprintf\(.*(SELECT|INSERT|UPDATE|DELETE)'`、`+ " WHERE` |
| `go/secrets-hardcoded` | blocker | トークン・パスワード・鍵がソースに無い | `grep -niE '(password|secret|token|apikey)\s*[:=]\s*"[^"]+"'` |
| `go/authz-missing` | blocker | 認可が必要なハンドラで所有者・権限チェックが抜けていない | ハンドラごとに「誰が呼べるか」を要件定義書と照合 |
| `go/error-dropped` | major | `_ = f()`・`err` の未使用・`if err != nil { return nil }`（err を捨てて nil を返す）が無い | `grep -nE '^\s*_\s*=\s*\w+\('`、`return nil$` の直前 |
| `go/errors-wrap` | major | 上位に返すエラーが `%w` で包まれ、文脈が付いている | `grep -nE 'return (err|fmt\.Errorf\(.*%v)'` |
| `go/context-missing` | major | I/O 関数が `ctx` を受け取り、下位に渡している | 関数シグネチャの第一引数、`context.Background()` / `TODO()` の使用箇所 |
| `go/goroutine-leak` | major | 起動した goroutine に終了条件がある | `go func` の周辺に WaitGroup / errgroup / `ctx.Done()` |
| `go/race` | major | `go test -race ./...` が通る | 実行して確認 |
| `go/interface-any` | major | `interface{}` / `any` を型の代わりに使っていない（JSON の動的部分以外） | `grep -nE '\bany\b|interface\{\}'` |
| `go/time-now-direct` | major | ビジネスロジックが `time.Now()` を直接呼んでいない（テスト可能性） | `grep -n 'time.Now()'` がハンドラ・サービス層にある |
| `go/panic-in-request` | major | リクエスト処理経路に `panic` が無い | `grep -n 'panic('` |
| `go/table-driven` | minor | 複数ケースのテストがテーブル駆動になっている | `_test.go` の構造 |
| `go/naming` | minor | パッケージ名・エクスポート名・レシーバ名（1〜2 文字で統一）が慣習どおり | 目視 |
| `go/doc-comment` | minor | エクスポート識別子に識別子名から始まる doc コメント | `golint` 相当 |
| `go/struct-positional` | minor | 構造体リテラルがフィールド名付き | `go vet` の composites |

## 標準コマンド（tech_stack が空のときのフォールバック）

| 用途 | コマンド |
|---|---|
| format | `gofmt -l . && goimports -l .`（差分が出たら失敗扱い） |
| lint | `go vet ./... && golangci-lint run ./...` |
| 型検査 | `go build ./...` |
| test | `go test -race -cover ./...` |

## 出典と対象バージョン

このファイルは執筆時点（2026-09）の知識で書かれている。`verified_against` より新しい / 古いバージョンでは [version-check.md](version-check.md) の手順で公式ドキュメントと照合し、差分は `doc/process/conventions_verified.md` が優先する。`[version-sensitive]` は変わりやすい項目、`[opinion]` は公式ではなくコミュニティの多数派・筆者の推奨で、`doc/conventions.md` で上書きしてよい。

| 項目 | 出典 | 備考 |
|---|---|---|
| verified_against | Go 1.23 | リリースノート未照合。1.22 以降の `net/http` ルーティング（メソッド・パスパラメータ）は未記載 `[version-sensitive]` |
| エラーの `%w`・`errors.Is/As` | https://go.dev/blog/go1.13-errors | |
| 命名・パッケージ・doc コメント | https://go.dev/doc/effective_go 、https://go.dev/wiki/CodeReviewComments | |
| `context` の受け渡し | https://go.dev/blog/context 、https://pkg.go.dev/context | |
| テーブル駆動テスト | https://go.dev/wiki/TableDrivenTests | |
| `util` パッケージ回避・インターフェースは使う側で定義 | https://go.dev/wiki/CodeReviewComments#interfaces 、https://google.github.io/styleguide/go/best-practices | `[opinion]` の色が強い |
| `time.Now()` の注入 | — | `[opinion]`（テスト可能性のための一般的手法） |
| リリースノート（照合用） | https://go.dev/doc/go{version} | `{version}` は `1.23` 形式 |
