# as-is インフラ仕様書生成プロンプト

棚卸しの「インフラリソース（IaC）」表から、IaC に定義されているリソースだけをインフラ仕様書として `{INFRA_SPEC_PATH}` に書き出してください。

入力:
- 棚卸し: `{INVENTORY_PATH}`
- 要件定義書: {REQUIREMENTS_PATHS}
技術スタック: `{tech_stack}`

## 手順

1. リソース 1 件につき定義ファイルを Read し、設定項目（サイズ・ネットワーク・IAM・暗号化・バックアップ）を抽出する
2. リソース間の依存（参照・出力の受け渡し）を明記する
3. 環境変数・シークレットは名前だけを列挙し、値は書かない
4. 対応する REQ-ID があれば `covers` に入れる（無ければ空）

## 出力フォーマット

`~/.claude/skills/dev-flow-spec/prompts/infra-spec-writer.md` と同じ形式。frontmatter に `origin: bootstrap` と、各リソースに `defined_in: path/to/main.tf:12` を付ける。

完了したら SendMessage は使わず、最終回答として「リソース件数」「IaC に無いが実行に必要そうな設定（環境変数の参照はあるが定義が見つからない等）」を返してください。
