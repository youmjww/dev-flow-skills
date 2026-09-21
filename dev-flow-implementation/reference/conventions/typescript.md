# TypeScript

React / Next.js の土台。`react.md` / `nextjs.md` はこのファイルの上に読む。

## 書き方（implementer 向け）

### 命名・構成
- `strict: true`（`noImplicitAny` / `strictNullChecks` 含む）を前提に書く。`// @ts-ignore` は禁止、やむを得ない場合は `// @ts-expect-error` に理由を添える
- 変数・関数は `camelCase`、型・クラス・コンポーネントは `PascalCase`、定数は `UPPER_SNAKE`（モジュールスコープの真の定数のみ）
- `type` と `interface` はプロジェクトの既存に合わせる（混在させない）。無ければオブジェクト形状は `type`、拡張前提の公開契約は `interface`
- `enum` より `as const` のユニオン（`const Status = { Active: "active" } as const; type Status = typeof Status[keyof typeof Status]`）
- 1 ファイル 1 責務。`utils.ts` / `helpers.ts` / `common.ts` にまとめない
- `export default` はフレームワークが要求する場合（Next.js のページ等）のみ。それ以外は名前付き export

### エラー処理
- `catch (e)` の `e` は `unknown`。`instanceof` で絞ってから使う
- 失敗しうる処理の戻り値で「成功 / 失敗」を表す場合は判別可能ユニオン（`{ ok: true; value } | { ok: false; error }`）。`null` を多義的に使わない
- Promise を投げっぱなしにしない（`void promise` で明示するか `await`）。未処理の rejection を作らない
- 外部入力（HTTP body、環境変数、`JSON.parse` の結果）は `zod` 等でランタイム検証してから型を付ける。`as` で信じない

### 並行処理・非同期
- `async` 関数の呼び出しは必ず `await` するか、意図的に並列なら `Promise.all` / `allSettled`。ループ内の逐次 `await` は意図が無ければ `Promise.all` に
- `setTimeout` / イベントリスナーはクリーンアップとセットで書く
- キャンセルが必要な fetch には `AbortController` を渡す

### 依存・境界
- 環境変数は起動時に 1 か所で検証・型付けし（`env.ts`）、各所で `process.env.X` を直接読まない
- `any` を返すライブラリの境界には型ガード関数を置く
- `Date` の直接生成をビジネスロジックに埋めない（注入するか、`date-fns` 等で純粋関数に）

### テスト
- `vitest`（または `jest`）。`describe("login")` + `it("returns 401 when password is wrong")`。TC-ID をテスト名かコメントで対応付ける
- 複数ケースは `it.each` / `test.each`
- モックは境界（HTTP・DB・時計）に限定。`vi.mock` で自モジュールを差し替え始めたら設計を疑う
- 型のテストが必要なら `expectTypeOf` / `// @ts-expect-error` を使う

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `ts/secrets-hardcoded` | blocker | トークン・鍵がソースに無い。`NEXT_PUBLIC_` / クライアントバンドルに秘密を出していない | `grep -niE '(secret|token|api_key|apikey)\s*[:=]\s*["\x27][^"\x27]+'` |
| `ts/injection` | blocker | SQL / シェル / HTML を文字列結合で組み立てていない | `grep -nE '\$\{.*\}.*(SELECT|INSERT|exec\(|innerHTML)'` |
| `ts/authz-missing` | blocker | 認可が必要な API ルート・Server Action で権限チェックが抜けていない | ルートごとに要件定義書と照合 |
| `ts/ts-ignore` | major | `@ts-ignore` / `as any` / `as unknown as X` が無い | `grep -nE '@ts-ignore|as any|as unknown as'` |
| `ts/any` | major | 明示的 `any` が無い（型が無いライブラリの境界以外） | `grep -nE ':\s*any\b|<any>'` |
| `ts/unvalidated-input` | major | 外部入力がランタイム検証されている | `JSON.parse` / `req.body` / `searchParams` の直後に検証があるか |
| `ts/floating-promise` | major | 未 await の Promise が無い | `@typescript-eslint/no-floating-promises` |
| `ts/catch-unknown` | major | `catch` の変数を絞らずに使っていない | `catch (e)` の直後で `e.message` 等 |
| `ts/sequential-await` | major | 独立した非同期処理をループで逐次 `await` していない | `for` 内の `await` |
| `ts/env-direct` | major | `process.env` を各所で直接読んでいない | `grep -n 'process.env'` が `env.ts` 以外 |
| `ts/enum` | minor | `enum` より `as const` | `grep -n '^enum\|^export enum'` |
| `ts/default-export` | minor | 不要な `export default` | `grep -n 'export default'` |
| `ts/test-each` | minor | 複数ケースが `it.each` | テストの構造 |

## 標準コマンド（tech_stack が空のときのフォールバック）

| 用途 | コマンド |
|---|---|
| format | `prettier --check .` |
| lint | `eslint .` |
| 型検査 | `tsc --noEmit` |
| test | `vitest run`（または `jest --ci`） |
