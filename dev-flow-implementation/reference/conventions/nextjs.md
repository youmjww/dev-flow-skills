# Next.js（App Router）

`typescript.md` → `react.md` の上に読む。Pages Router のプロジェクトでは「App Router 固有」の項目を読み替える（`getServerSideProps` 等）。

**バージョンで大きく変わる領域**（必ず version-check で照合）: キャッシュ既定値（14 → 15 で `fetch` が非キャッシュに）、`params` / `searchParams` / `cookies()` / `headers()` の非同期化（15）、Cache Components / `'use cache'`（16、`cacheComponents` フラグ）、`revalidateTag` の第 2 引数（16）。

## 書き方（implementer 向け）

### サーバー / クライアントの境界
- 既定は **Server Component**。`"use client"` はインタラクション（state・イベント・ブラウザ API）が必要な末端のコンポーネントにだけ付け、ツリーの上の方に付けない
- Server Component から Client Component に渡す props はシリアライズ可能な値のみ（関数・クラスインスタンス・`Date` は不可）
- データ取得は Server Component で `fetch` / DB 直接呼び出し。Client Component で初期データを `useEffect` fetch しない
- 秘密（DB 接続文字列・API キー）は Server Component / Route Handler / Server Action でのみ触る。`NEXT_PUBLIC_` を付けた瞬間クライアントに露出する
- `server-only` パッケージを import してサーバー専用モジュールの誤 import をビルド時に検出する

### ルーティング・ファイル構成
- `app/` 配下は `page.tsx` / `layout.tsx` / `loading.tsx` / `error.tsx` / `route.ts` の役割を守る。ページファイルにロジックを書かず、`features/` や `lib/` に置く
- ルートグループ `(group)` で URL に出さない構造化。`_` 始まりのフォルダはプライベート
- `error.tsx` は Client Component 必須。`not-found.tsx` で 404 を明示

### データ変更（Server Actions / Route Handlers）
- フォーム送信・変更は Server Action を第一候補。外部から呼ばれる API は Route Handler
- Server Action / Route Handler の入力は **必ず** `zod` 等でランタイム検証する（クライアントから何でも送れる）
- Server Action の中で認証・認可を毎回確認する（ページで確認していてもアクションは直接呼べる）
- 変更後は `revalidatePath` / `revalidateTag` でキャッシュを無効化する。忘れると古いデータが出続ける。16 では `revalidateTag(tag, 'max')` のように第 2 引数（プロファイル）を取る `[version-sensitive]`
- `redirect()` は `try/catch` の外で呼ぶ（内部的に throw するため）

### キャッシュ・レンダリング
- `fetch` のキャッシュ挙動（`cache` / `next.revalidate` / `tags`）を明示する。**15 以降の既定は非キャッシュ**（`cache: 'force-cache'` で明示的にキャッシュ）。14 以前は既定キャッシュだったので、バージョンを確認せずに書かない `[version-sensitive]`
- 15 以降、`params` / `searchParams`（ページ・レイアウト・Route Handler）と `cookies()` / `headers()` は **Promise**。`const { id } = await params` のように `await` する `[version-sensitive]`
- 16 の Cache Components（`cacheComponents: true`）を使うプロジェクトでは `'use cache'` ディレクティブと `cacheLife` / `cacheTag` が主役になり、`unstable_cache` / `fetchCache` 等の旧モデルは使わない。どちらのモデルかを `next.config` で確認する `[version-sensitive]`
- `fetch` を使わない DB アクセスの重複排除は React の `cache()`、キャッシュは `unstable_cache`（旧モデル）または `'use cache'`（Cache Components）
- 動的にすべき理由（cookie・headers・検索パラメータ）が無ければ静的にする。`export const dynamic = "force-dynamic"` を安易に付けない
- `loading.tsx` / `Suspense` でストリーミング。ページ全体を 1 つの `await` で止めない

### 画像・メタデータ
- `next/image` を使い、`width` / `height` または `fill` を指定。外部ドメインは `next.config` の `images.remotePatterns` に登録
- `next/link` でナビゲーション。`<a href>` で内部遷移しない
- `metadata` / `generateMetadata` でタイトル・OGP を設定

### テスト
- ユニットは `react.md` の方針。Server Component は関数として呼んでレンダリング結果を検証できる
- Server Action / Route Handler は関数として直接テスト（`Request` を組み立てる）
- E2E は Playwright。認証が絡むフローは E2E で 1 本は必ず通す

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `next/secret-public` | blocker | `NEXT_PUBLIC_` に秘密が無い。Client Component からサーバー専用モジュールを import していない | `grep -n 'NEXT_PUBLIC_'`、`server-only` の有無 |
| `next/action-unvalidated` | blocker | Server Action / Route Handler の入力がランタイム検証されている | `"use server"` 関数と `route.ts` の先頭 |
| `next/action-authz` | blocker | Server Action / Route Handler 内で認証・認可を確認している | 各アクションの先頭 |
| `next/use-client-top` | major | `"use client"` がツリーの上位（layout / page）に付いていない | `grep -ln '"use client"' app/**/layout.tsx app/**/page.tsx` |
| `next/client-fetch` | major | Client Component で初期データを `useEffect` fetch していない | `"use client"` ファイル内の `fetch` |
| `next/revalidate-missing` | major | データ変更後に `revalidatePath` / `revalidateTag` がある | 変更系アクションの末尾 |
| `next/redirect-in-try` | major | `redirect()` が `try` の中に無い | `grep -n 'redirect('` の周辺 |
| `next/force-dynamic` | major | `force-dynamic` に根拠がある | `grep -n 'force-dynamic'` |
| `next/nonserializable-props` | major | Server → Client の props に関数・`Date` が無い | 境界コンポーネントの props 型 |
| `next/img-tag` | minor | `<img>` / `<a href="/...">` を使っていない | `grep -nE '<img |<a href="/'` |
| `next/metadata` | minor | ページに `metadata` がある | `page.tsx` |
| `next/loading` | minor | 重いページに `loading.tsx` / `Suspense` | ディレクトリ構成 |

## 標準コマンド

| 用途 | コマンド |
|---|---|
| format | `prettier --check .` |
| lint | `next lint`（または `eslint .`） |
| 型検査 | `tsc --noEmit` |
| test | `vitest run` + `playwright test`（E2E） |
| build | `next build`（型・サーバー/クライアント境界エラーはここで出る。PR 前に必ず通す） |

## 出典と対象バージョン

このファイルは執筆時点（2026-09）の知識で書かれている。`verified_against` より新しい / 古いバージョンでは [version-check.md](version-check.md) の手順で公式ドキュメントと照合し、差分は `doc/process/conventions_verified.md` が優先する。`[version-sensitive]` は変わりやすい項目、`[opinion]` は公式ではなくコミュニティの多数派・筆者の推奨で、`doc/conventions.md` で上書きしてよい。

| 項目 | 出典 | 備考 |
|---|---|---|
| verified_against | Next.js 16.3（2026-09-21、キャッシュのページのみ） | 他のページは未照合。ドキュメントは常に最新版のみで、旧バージョンは https://github.com/vercel/next.js/tree/v{version}/docs を参照 `[version-sensitive]` |
| ドキュメント索引（version-check の入口） | https://nextjs.org/docs/llms.txt | |
| キャッシュ（旧モデル） | https://nextjs.org/docs/app/guides/caching-without-cache-components | 「fetch requests are not cached by default」（16.3 で確認） |
| Cache Components / `'use cache'` | https://nextjs.org/docs/app/getting-started/caching 、https://nextjs.org/docs/app/api-reference/config/next-config-js/cacheComponents | 16 で導入 |
| Server / Client Components | https://nextjs.org/docs/app/getting-started/server-and-client-components | |
| Server Actions・データ変更 | https://nextjs.org/docs/app/getting-started/mutating-data | |
| `server-only` | https://www.npmjs.com/package/server-only | |
| Route Handlers | https://nextjs.org/docs/app/api-reference/file-conventions/route | |
| `revalidatePath` / `revalidateTag` | https://nextjs.org/docs/app/api-reference/functions/revalidatePath 、https://nextjs.org/docs/app/api-reference/functions/revalidateTag | |
| 非同期 `params` / `cookies` | https://nextjs.org/docs/app/api-reference/file-conventions/page | 15 の破壊的変更 |
| `next/image` / `next/link` / `metadata` | https://nextjs.org/docs/app/api-reference/components/image 、https://nextjs.org/docs/app/api-reference/functions/generate-metadata | |
| Server Action 内で毎回認可 | https://nextjs.org/docs/app/guides/authentication | |
| アップグレードガイド（照合用） | https://nextjs.org/docs/app/guides/upgrading | |
