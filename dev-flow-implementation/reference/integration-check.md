# STEP C.5: Dev + QA 統合検証の手順

`dev-flow-implementation/SKILL.md` STEP C.5 から参照。

**手順（グループごと、Dev/QA 両方の implementer が `completed` を返した後）:**

1. QA worktree に Dev ブランチを**検証用に**マージする（QA 側で行う。Dev 側には QA を混ぜない）：
   ```bash
   cd {MAIN_DIR}/../worktree-qa-{team}-group-N
   git merge dev/{team}-group-N -m "merge: 検証用（後で取り消す）"
   ```
   - **コンフリクトした場合**: 同じパスのファイルを Dev/QA 双方が作っている。テストファイルなら QA 側を正とし、Dev implementer に「そのファイルを `git rm` して再コミット」を `SendMessage` で依頼する。実装ファイルなら QA 側の変更を取り消す
2. QA worktree で **Dev のユニットテストと QA の仕様テストの両方**・lint・型検査を**実際に実行**する（`tech_stack` の標準コマンド。依存物が無ければ `composer install` / `npm install` 等を先に行う）。あわせて規約の「標準コマンド（分岐カバレッジ）」で統合カバレッジを計測し、参考値として STEP E の PR 説明に書く（ゲートは Dev の `result.coverage` で既に掛かっているので、ここでは記録のみ）
3. 結果で分岐：
   | 結果 | 対応 |
   |---|---|
   | 全パス | 4 へ |
   | テストコード側の不備（セットアップ漏れ・文言のタイプミス・セレクタの推測違い等） | QA implementer に `SendMessage` で修正を依頼する（軽微で明白なら オーケストレーターが直接直してもよい）。直った後 1 からやり直す |
   | 実装側の不備（QA の期待がテスト定義書どおりで、実装がそれに従っていない） | Dev implementer に `SendMessage` で修正を依頼する。直った後 1 からやり直す |
   | テスト定義書自体の矛盾 | STEP G の `doc_issues` として扱い、人間に判断を仰ぐ |
4. 検証用マージを**必ず取り消す**（PR の diff に Dev の変更が混ざらないようにする）：
   ```bash
   git reset --hard {マージ前の QA コミット}
   ```
   取り消し前に QA 側で修正コミットを積んだ場合は、`git stash` → `reset --hard` → `stash pop` → 再コミットで修正だけを残す
5. 統合で全パスした事実（Dev ユニットテスト件数 + QA 仕様テスト件数、統合カバレッジ）を STEP E の PR 説明に書く

この STEP を飛ばすと、レビュアーが「QA テストは Dev 実装に対して通るか」を自前で検証することになり時間が掛かるうえ、PR マージ後の test ステージで初めて失敗が露見する。
