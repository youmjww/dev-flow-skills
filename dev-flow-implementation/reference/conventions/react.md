# React

`typescript.md` の上に読む。Next.js の場合はさらに `nextjs.md` を読む。

## 書き方（implementer 向け）

### コンポーネント設計
- 関数コンポーネントのみ。`React.FC` は使わず `function Button(props: ButtonProps)` の形（`children` は明示的に型付け）
- 1 ファイル 1 コンポーネント（小さな内部専用コンポーネントは例外）。ファイル名はコンポーネント名と一致（`UserCard.tsx`）
- Props は `type XxxProps`。真偽値 props は `is` / `has` / `can` で始める。イベントハンドラ props は `onXxx`、実装側は `handleXxx`
- 表示（presentational）とデータ取得・状態（container / hook）を分ける。JSX の中に `fetch` を書かない
- 条件付きレンダリングで `{count && <X />}` を書かない（`0` が描画される）。`{count > 0 && <X />}` か三項演算子

### state と副作用
- `useState` は UI の状態だけ。サーバーデータは TanStack Query / SWR / フレームワークのデータ層に任せ、`useEffect` + `useState` で fetch しない
- `useEffect` は「外部システムとの同期」にだけ使う。派生値は `useMemo` か描画時の計算、イベント応答はハンドラに書く。依存配列の lint 警告を `eslint-disable` で消さない
- `useEffect` で購読・タイマー・リスナーを張ったら必ずクリーンアップ関数を返す
- state の更新は前の値に依存するなら関数形式（`setCount(c => c + 1)`）
- グローバル状態は本当に横断するものだけ（認証ユーザー・テーマ）。フォームの入力値をグローバルに置かない
- `key` に配列の index を使わない（並び替え・削除があるリスト）

### パフォーマンス
- `useMemo` / `useCallback` / `memo` は計測して必要と分かってから。先回りで付けない
- 大きなリストは仮想化（`@tanstack/virtual` 等）
- 画像は `width` / `height` を指定し、遅延読み込みを使う

### アクセシビリティ
- `<div onClick>` でボタンを作らない。`<button>` / `<a>` を使う
- フォーム要素には `<label>` を対応付ける。アイコンだけのボタンには `aria-label`
- 色だけで状態を表さない

### テスト
- `@testing-library/react`。`getByRole` > `getByLabelText` > `getByText` の優先順で、`getByTestId` は最後の手段
- ユーザー操作は `@testing-library/user-event`（`fireEvent` より実際の挙動に近い）
- 非同期は `findBy*` / `waitFor`。`act` を直接呼ばない
- 実装の詳細（state の値、内部関数の呼び出し回数）をテストしない。ユーザーから見える結果をテストする

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `react/xss` | blocker | `dangerouslySetInnerHTML` に未サニタイズの外部入力を渡していない | `grep -n 'dangerouslySetInnerHTML'` |
| `react/secret-in-client` | blocker | クライアントコンポーネントに秘密（サーバー用トークン等）が渡っていない | props / 環境変数の流れ |
| `react/effect-fetch` | major | `useEffect` 内で `fetch` して `useState` に入れていない | `grep -n 'useEffect'` の中身 |
| `react/effect-cleanup` | major | 購読・タイマー・リスナーにクリーンアップがある | `addEventListener` / `setInterval` / `subscribe` の周辺 |
| `react/effect-deps-disabled` | major | `react-hooks/exhaustive-deps` を無効化していない | `grep -n 'eslint-disable.*exhaustive-deps'` |
| `react/index-key` | major | 動的リストの `key` に index を使っていない | `grep -nE 'key=\{(i|idx|index)\}'` |
| `react/stale-closure` | major | 前の値に依存する更新が関数形式 | `setX(x + 1)` の形 |
| `react/div-button` | major | クリック可能要素が `button` / `a` | `grep -n '<div onClick'` |
| `react/zero-render` | minor | `{n && <X />}` の `0` 描画バグが無い | `grep -nE '\{\w+(\.length)? &&'` |
| `react/premature-memo` | minor | 根拠のない `useMemo` / `useCallback` / `memo` | 数が多い場合に理由を聞く |
| `react/test-query` | minor | テストが `getByRole` 優先で `getByTestId` 頼みでない | テストの構造 |
| `react/label` | minor | フォーム要素に `label`、アイコンボタンに `aria-label` | 目視 |

## 標準コマンド

`typescript.md` と同じ。lint に `eslint-plugin-react-hooks` と `eslint-plugin-jsx-a11y` が入っていることを確認する。
