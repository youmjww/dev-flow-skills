# Next.js（App Router）

`typescript.md` → `react.md` の上に読む。Pages Router のプロジェクトでは「App Router 固有」の項目を読み替える（`getServerSideProps` 等）。

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
- 変更後は `revalidatePath` / `revalidateTag` でキャッシュを無効化する。忘れると古いデータが出続ける
- `redirect()` は `try/catch` の外で呼ぶ（内部的に throw するため）

### キャッシュ・レンダリング
- `fetch` のキャッシュ挙動（`cache` / `next.revalidate` / `tags`）を明示する。既定挙動はバージョンで変わるので暗黙に頼らない
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
