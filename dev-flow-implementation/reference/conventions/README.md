# 言語・フレームワーク別の規約とレビューチェックリスト

implementer（書く側）と reviewer（照合する側）の両方に注入する。`dev-flow-implementation/SKILL.md` STEP B / STEP D を参照。

## 選択ルール

`state.json.tech_stack` から次の順で選び、**すべて**注入する（後のものが前のものを上書き・補足する）：

| 順 | ソース | 例 |
|---|---|---|
| 1 | `conventions/<language>.md` | `language: Go` → `go.md`、`TypeScript` → `typescript.md`、`PHP` → `php.md`、`Python` → `python.md` |
| 2 | `conventions/<framework>.md`（あれば） | `framework: Next.js` → `nextjs.md`（`react.md` も先に読む）、`Laravel` → `laravel.md`、`React` → `react.md` |
| 3 | `{project}/doc/conventions.md`（あれば） | プロジェクト固有の規約。言語・フレームワーク規約と矛盾する場合はこちらが優先 |
| 4 | プロジェクトの `CLAUDE.md` | サブエージェントが自動で読む。規約が書かれていればレビュー基準として扱う |

言語名の正規化: 大文字小文字・`.js` の有無・`Golang` / `Go` の揺れは無視して一致させる。対応ファイルが無い言語は `_template.md` の観点だけで進め、最終回答で「規約ファイル未整備: {language}」と報告する。

## 各ファイルの構成

| セクション | 誰が使う | 内容 |
|---|---|---|
| 書き方 | implementer | 命名・構成・エラー処理・並行処理・依存・テストの書き方 |
| レビューチェックリスト | reviewer | ルール ID（`go/errors-wrap` 形式）・重大度・確認方法。**blocker / major は修正必須、minor は記録のみ** |
| 標準コマンド | 両方 | lint / format / test / 型検査。`tech_stack.linter` 等が空のときのフォールバック |

重大度の基準：

| 重大度 | 意味 | 例 |
|---|---|---|
| `blocker` | マージしてはいけない | 認証・認可の欠落、インジェクション、シークレットのハードコード、データ破壊、テスト改変 |
| `major` | 動くが後で確実に困る | エラーの握りつぶし、context / cancel の無視、N+1、型の抜け穴（`any` / `interface{}` の濫用）、境界値未テスト |
| `minor` | 直せると良い | 命名、コメント、軽微な重複、並び順 |

ルール ID は memory への蓄積キーになる（「`go/errors-wrap` が 3 回指摘された」を数えられるようにするため）。同じ問題には必ず同じ ID を使うこと。
