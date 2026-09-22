# dev-flow 実戦振り返り（2026-09-22）と PR 作成依頼

このファイルは、dev-flow スキル一式を使って「最小限のタスク管理アプリ（Laravel + React）」を要件定義から compliance まで一気通貫で作った実戦セッションの振り返りです。セッション中にスキルへ加えた修正が **このリポジトリの作業ツリーに未コミットの状態で入っています**。このファイルを読んだ Claude セッションは、末尾の「PR 作成依頼」に従ってコミットと PR を作ってください。

対象プロジェクト: `~/project/private/sample`（GitHub: `youmjww/sample`、private）。全 6 ステージ完了、PR #1〜#7 マージ済み、最終テスト 65/65 パス。

---

## 1. 詰まった箇所（重要度順）

### 1-1. pane 型サブエージェントが起動後に何もせずハングする【最重要・環境起因】

- **症状**: `Agent` ツールで起動した名前付きサブエージェント（ListAgents で `pane` と表示される通常のもの）が、起動後にツールを一切実行しないまま無期限に止まる。`flow.log` には `agent_start` と `agent_complete duration_seconds=0` が同時刻に並ぶ。SendMessage で生存確認しても応答なし。最小タスク（`echo` 1 回 + Write 1 回）でも再現。
- **発生回数**: 実装エージェント 7 回、レビュアー 4 回、`stage-implementation-agent` 1 回、`test-runner-haiku` 1 回。**このセッションで pane 型で起動して正常動作したのは spec / consistency ステージの writer / checker のみ**で、implementation 以降はほぼ全滅だった。
- **切り分け**: `subagent_type: "fork"` で同じプロンプトを起動すると 3.6 秒で正常完了。fork 経由の実装・レビュー・テスト実行はすべて成功。
- **原因**: 不明（Claude Code 側。`SendFeedback` で報告済み）。`model` 指定や `run_in_background` の有無とは無関係。
- **対策（スキル修正済み）**: `dev-flow/reference/agent-hang-recovery.md` を新設。検知手順（タイムアウト目安の半分でファイル変化を見る → SendMessage で生存確認 → 最終判定）と fork フォールバック手順を定義し、`dev-flow/SKILL.md` STEP 3.5・`dev-flow-implementation/SKILL.md` STEP B/C から参照。全ステージの `allowed-tools` に `SendMessage` `TaskStop` を追加（フォールバック手順に必要だったが無かった）。

### 1-2. fork は `Agent` ツールで子サブエージェントを起動できない【1-1 の派生】

- **症状**: ハングした `stage-implementation-agent` を fork で再起動したところ、「fork のハードルールで `Agent` ツールが使えないため、Dev/QA/レビュアーを起動する設計のこのステージは実行できない」と報告して終了した。
- **影響**: `stage-*-agent`（オーケストレーターが起動する中間管理エージェント）には fork フォールバックが効かない。末端の実行者（implementer / reviewer / writer / test-runner）には効く。
- **対策（スキル修正済み）**: `agent-hang-recovery.md` に「適用範囲」節を追加し、中間管理エージェントがハングした場合は **オーケストレーター（`/dev-flow` を実行しているセッション自身）が該当ステージの SKILL.md を読んで STEP 0 以降を直接実行する** 手順を明記。`dev-flow/SKILL.md` STEP 3.5 にも同旨を追記。実際にこの方式で implementation / test / compliance を完走した。
- **未解決の副作用**: fork は `model` を無視して親と同じモデルで動く。今回オーケストレーターが Sonnet 5 だったので、本来 opus で回すレビュアーも haiku で回す test-runner も Sonnet で動いた。コスト最適化が効かない。

### 1-3. CI が無い新規プロジェクトでは自動マージが一切できない

- **症状**: `pr-merge-guard.sh` が「CI チェックが無い PR は自動マージしない」で deny。新規プロジェクトには CI が無いので、最初の PR から全部止まる。
- **対策（スキル修正済み）**: `dev-flow-consistency/prompts/checklist-writer.md` に「新規プロジェクトセットアップ時は最小限の CI（lint / 型検査 / テスト）設定タスクを基盤グループに含める」ルールを追加。
- **付随して詰まった点**:
  - `.github/workflows/*.yml` の push には gh トークンの `workflow` スコープが必要で、`gh auth refresh -s workflow` のデバイス認証（人間のブラウザ操作）が要った → checklist-writer.md の CI ルールに注記追加
  - CI の PHP バージョンを要件定義書の 8.3 にしたら、ローカル 8.5 で作った composer.lock の依存が解決できず失敗 → 同じく注記追加（実バージョンと lock に合わせる）

### 1-4. CLAUDE.md の「PR は Draft」ルールと自動マージが衝突

- **症状**: プロジェクトのグローバル CLAUDE.md に「PR は Draft として作成する」があり、それに従うと `gh pr merge` が通らない。
- **対策（スキル修正済み）**: `dev-flow-implementation/SKILL.md` STEP E に「PR は Draft ではなく OPEN で作る。dev-flow は STEP D でレビュー済みの状態で PR を作るので Draft にする理由が無い」と明記。ユーザー側でも CLAUDE.md に「スキル経由で作成された PR はその限りではない」の例外が追記された。

### 1-5. DB 破壊的変更パターンの誤検知

- **症状**: QA が書いた SQL インジェクション対策テスト（TC-024）のテストデータ `"'; DROP TABLE tasks; --"` が `db-destructive-patterns.txt` の `DROP[[:space:]]+TABLE` にマッチし、`pr-merge-guard.sh` が deny。人間の手動マージが必要になった。
- **対策（スキル修正済み・部分）**: STEP G に「deny 理由の分類表（安全装置の正常動作か誤検知かの見分け方）」と「理由を `gh pr comment` で PR 自体に残す手順」を追加。hook 自体は触っていない。
- **改善提案（未対応、§3 参照）**: hook 側でテストファイルを DB 検査から除外する。

### 1-6. Dev と QA が同じファイルを別 worktree で作ってしまう

- **症状 1（グループ 2）**: Dev implementer が「動作確認のため」に `backend/tests/Feature/TaskApiTest.php` を書き、QA も同じパスに本番テストを書いた。マージ時にコンフリクト。
- **症状 2（グループ 5 = E2E）**: Dev/QA 双方が `e2e/` ディレクトリ一式（package.json / playwright.config.ts / tests/*.spec.ts）を独立に実装。完全重複。
- **原因**: Dev プロンプトに「テストから呼び出しやすいインターフェース設計にする」とあり、Dev がテストまで書く方向に解釈した。E2E はチェックリスト生成時点で Dev/QA のタスクが実質同じ内容になっていた。
- **対策（スキル修正済み。途中で方針転換あり）**:
  - 最初は `prompts/dev-app.md` `dev-infra.md` に「テストコードは書かない（QA の担当）」と書いたが、**これは行き過ぎだった**。ユーザーの指摘（「QA が書くのは仕様単位のブラックボックステスト。Dev にもユニットテストを書かせるべき」）を受けて撤回し、**種類と置き場で分ける**ルールに変更した（→ 1-14）
  - `checklist-writer.md` に「E2E グループは Dev タスクのみにする（分ける場合はファイルパス単位で担当を明記）」ルールを追加
  - `dev-flow-implementation/SKILL.md` STEP A に「QA タスクが無いグループは QA worktree / ブランチを作らない」を追記

### 1-7. QA テストが Dev 実装と噛み合わない（統合してみないと分からない）

- **症状**: QA は Dev 実装を見ずにインターフェースを推測してテストを書く。統合すると 25 件中 19 件失敗（React Testing Library の `afterEach(cleanup)` 未登録で DOM が残留、404 メッセージの句点有無、aria-label の推測違い）。レビュアーに回す前にオーケストレーターが手動で Dev→QA を検証マージし、修正し、マージを取り消す作業が毎グループ必要だった。
- **対策（スキル修正済み）**: `dev-flow-implementation/SKILL.md` に **STEP C.5「Dev + QA 統合検証」** を新設。QA worktree に Dev ブランチを検証用マージ → 実テスト実行 → 不備は該当 implementer に差し戻し → 検証マージを `reset --hard` で取り消す、という手順を明記。

### 1-8. QA 側 PR の CI が単体では通らない

- **症状**: QA ブランチには Dev 実装が無いので CI が必ず 404 で失敗。Dev PR を先にマージし、QA PR を `gh api .../update-branch` で最新化してから CI 再実行が必要だった。
- **対策（スキル修正済み）**: STEP G に「Dev PR → QA PR の順でマージ。QA PR は Dev マージ後に `update-branch` して CI を再走させる。QA PR の CI 失敗を実装不備と誤解しない」を追記。

### 1-9. `mergeable=UNKNOWN` の一時状態で hook が deny

- **症状**: PR を 1 本マージした直後、次の PR の `mergeable` が数秒〜十数秒 `UNKNOWN`（GitHub 側の再計算中）になり hook が deny。
- **対策（スキル修正済み）**: STEP G に「`gh pr view --json mergeable,mergeStateStatus` で `MERGEABLE`/`CLEAN` を確認してから再試行。`CONFLICTING` なら本当のコンフリクト」を追記。あわせて「`gh pr merge` を `&&` で他コマンドと連結すると hook が PR 番号を解析できず deny する」も追記（実際に踏んだ）。

### 1-10. 環境固有の注意（nvm / composer / timeout / ポート）を毎回全エージェントに手書きした

- **症状**: このマシンは非対話シェルで nvm が自動ロードされず Node v10 が使われる。`composer create-project` は `--no-interaction` と `timeout` が無いと固まる。E2E は残留プロセスがポート 8000/5173 を握っていると起動できない。これらを Dev/QA/レビュアー/test-runner の全プロンプトに毎回コピペする必要があり、書き漏らしたエージェントが失敗した。
- **対策（スキル修正済み）**: `reference/agent-prompt-injection.md` に「実行環境ノートの注入」節を追加。`doc/process/environment.md` があれば全エージェントのプロンプト冒頭に注入する。`dev-flow-implementation/SKILL.md` STEP B の注入リストに 1.5 として追加。

### 1-11. 要件定義書のバージョン表記と実環境の乖離

- **症状**: 要件定義書は PHP 8.3 / Laravel 12 / Vite 6 だったが、composer / npm が取得したのは PHP 8.5 / Laravel 13 / Vite 8 / TypeScript 6 / Pest 4 / Vitest 5。compliance で乖離として検出され、人間判断で要件定義書側を更新した。
- **対策**: スキル修正はしていない（`conventions/version-check.md` の仕組みはあるが、今回は WebFetch を使わず「未検証」で進めた）。**改善提案**: implementation の最初のグループ完了時（`composer.lock` / `package-lock.json` が確定した時点）に、`tech_stack` の実バージョンを state.json と要件定義書に書き戻す STEP を bootstrap 以外にも置く。

### 1-12. `agent-complete.sh` がハング中でも「完了（0秒）」と記録する

- **症状**: pane 型は `run_in_background: false` でも Agent ツール呼び出しが即座に返るため、PostToolUse の `agent-complete.sh` が起動直後に発火し、`agent_complete duration_seconds=0` を記録する。実際は何も完了していない。
- **副作用**: ハング検知の手がかりにはなった（0 秒完了 = 怪しい）が、`flow.log` の記録としては誤り。
- **改善提案（未対応、§3 参照）**。

### 1-13. その他（軽微）

- `ScheduleWakeup` で登録した古いプロンプトが、その用件が完了した後も何度も再送される（Claude Code 側の挙動。スキルの問題ではない）
- Bash の python3 heredoc 内で `$` を含む文字列を扱うとエスケープが要る（`old` 文字列に `\$response` と書くと一致しない）
- 一度 pane 型で完了したエージェントも ListAgents に「started Nh ago」で残り続け、11 件溜まった（ユーザー指示で一括 TaskStop）

### 1-14. Dev / QA のテスト分担が「テストは QA」で曖昧だった【設計変更】

- **症状**: 従来の設計は「Dev は実装、QA はテスト」で、`testing.md` の `test/branch-coverage`（実装の分岐ごとに 1 ケース）も QA implementer の責務だった。しかし QA は Dev 実装を見ずにテスト定義書から書くので、**実装内部の分岐は原理的に網羅できない**。実際、`TaskResource` が日時を UTC で返すバグ（仕様は `+09:00`）は QA の Feature テスト 37 件では検出されず、Dev レビュアーが手動で見つけた。Dev レビューが「TC 不足」を QA に差し戻す回り道も発生した。一方 1-6 のとおり Dev が Feature テストまで書くと QA と衝突する。
- **原因**: テストの**種類**（ユニット / 仕様）と**担当**（Dev / QA）の対応が定義されておらず、「テスト」を一括りに QA へ寄せていた。
- **対策（スキル修正済み）**: 「Dev = ユニットテスト（ホワイトボックス・分岐網羅・実装と対の置き場）、QA = 仕様テスト（ブラックボックス・TC 網羅・Feature / App 結合 / E2E）」に分担を定義。
  - `reference/conventions/testing.md`: 冒頭に「Dev と QA のテスト分担」表（種類・対象・網羅基準・置き場・モック・coverage の責務）と「書き方（Dev implementer 向け: ユニットテスト）」節を新設。QA 向けの「分岐ごとに 1 ケース」を「仕様の分岐ごとに 1 ケース（実装の `if` は数えない）」に変更。レビューチェックリストに担当列を付け、`test/branch-coverage` を Dev、新設の `test/tc-coverage` を QA、`test/unit-vs-spec-split`（置き場違反）を両方に。分岐カバレッジの `result.coverage` ゲートを QA から Dev に移動
  - `prompts/dev-app.md` `dev-infra.md`: 「自分が書いた関数のユニットテストを書く（置き場・分岐網羅・出力形式の検証）」「TC-ID 付きの仕様テストは書かない」。完了 JSON に `unit_tests` と `coverage` を追加
  - `prompts/qa-app.md` `qa-infra.md`: 「仕様テストに専念。`tests/Unit/**` 等のユニットテストは書かない」。実装が無い worktree では失敗が正常なので `result.tests` に件数と理由を書く形に変更（coverage 計測は不要に）
  - `dev-flow-implementation/SKILL.md`: STEP C の coverage ゲートを Dev に移動、QA の失敗は `note` で判定。STEP C.5 で Dev ユニット + QA 仕様の両方を実行し統合カバレッジを記録。STEP D の Dev レビューは「分岐に対応するユニットテストが Dev worktree にあるか」を見て **Dev に差し戻す**（QA に回さない）、QA レビューは TC 網羅と置き場を見る
  - `checklist-writer.md`: Dev タスクにユニットテストを含める旨（粒度の見積もりに反映）
- **未検証**: この分担で 1 周回していない。次の実戦で「Dev のユニットテストと QA の仕様テストが同じことを二重に検証していないか」「Dev worktree に実装が無い段階で QA が `App.test.tsx` を書くと、Dev がコンポーネント単位の `X.test.tsx` を書いた時に `src/test/setup.ts` 等の共有セットアップファイルで衝突しないか」を確認する必要がある。共有セットアップは基盤グループ（グループ 3 相当）で Dev が作る想定だが、明文化していない

---

## 2. このセッションで加えたスキル修正（すべて未コミット）

`git status` で見える差分。設計思想（モデル別コスト最適化・hook による決定的ガード・DocDD）は壊していない。

| ファイル | 変更内容 | 対応する詰まり |
|---|---|---|
| `dev-flow/reference/agent-hang-recovery.md` | **新規**。ハング検知手順・fork フォールバック・中間管理エージェントの扱い・既知の制約 | 1-1, 1-2 |
| `dev-flow/SKILL.md` | STEP 3.5 にハング切り分け→fork / オーケストレーター引き継ぎの手順を追記。`allowed-tools` に `SendMessage` `TaskStop` 追加 | 1-1, 1-2 |
| `dev-flow-spec/SKILL.md` `dev-flow-consistency/SKILL.md` `dev-flow-test/SKILL.md` `dev-flow-bootstrap/SKILL.md` | `allowed-tools` に `TaskStop`（spec/consistency）または `SendMessage` `TaskStop`（test/bootstrap）追加 | 1-1 |
| `dev-flow-implementation/SKILL.md` | STEP A: QA タスク無しグループは QA worktree を作らない / STEP B: ハング注記・実行環境ノート注入 / STEP C: タイムアウト超過時のハング判定、coverage ゲートを Dev に、QA の失敗は `note` で判定 / **STEP C.5 新設**: Dev ユニット + QA 仕様の統合検証 / STEP D: Dev レビューは分岐→ユニットテストを Dev に差し戻し、QA レビューは TC 網羅と置き場 / STEP E: PR は OPEN で作る / STEP G: deny 理由の分類表・PR コメントで理由明記・Dev→QA マージ順序・update-branch・UNKNOWN 再試行・コマンド連結禁止 | 1-1, 1-4〜1-10, 1-14 |
| `dev-flow-implementation/prompts/dev-app.md` `dev-infra.md` | ユニットテストを書く（置き場・分岐網羅・形式検証）、仕様テストは書かない、完了 JSON に `unit_tests` / `coverage` | 1-6, 1-14 |
| `dev-flow-implementation/prompts/qa-app.md` `qa-infra.md` | 仕様テストに専念、ユニットテストは書かない、`result.tests` で失敗理由を報告（coverage 不要に） | 1-14 |
| `dev-flow-implementation/reference/conventions/testing.md` | 「Dev と QA のテスト分担」表・Dev 向け書き方節を新設、QA 向けの分岐基準を仕様寄りに、チェックリストに担当列・`test/tc-coverage`・`test/unit-vs-spec-split` 追加、coverage 責務を Dev に | 1-14 |
| `dev-flow-implementation/reference/agent-prompt-injection.md` | 「実行環境ノートの注入」節を新設（`doc/process/environment.md`） | 1-10 |
| `dev-flow-consistency/prompts/checklist-writer.md` | CI 整備ルール（`workflow` スコープ・実バージョン合わせの注記付き）、E2E グループの Dev/QA 分担ルール、Dev タスクにユニットテストを含める注記 | 1-3, 1-6, 1-14 |

`bash tests/hooks/run.sh` は 132 passed（hook は触っていないので変化なし）。

---

## 3. 未対応の改善提案（PR 作成者の判断に委ねる）

スキル本文ではなく hook や仕組み側の変更で、テストや設計判断が要るためこのセッションでは手を付けていない。別 PR にするか、今回の PR に含めるかは任せる。

### 3-1. `pr-merge-guard.sh`: DB 破壊的変更検査からテストファイルを除外する

`db-destructive-patterns.txt` は「誤検知は自動マージしない側に倒れるだけ」という設計だが、テストファイル内の文字列リテラル（SQL インジェクション対策テストのデータ）で毎回止まるのは運用上つらい。案：

- `gh pr diff` の出力を `diff --git a/... b/...` ヘッダでファイル単位に分割し、パスが `tests/` `test/` `__tests__/` `e2e/` `*_test.*` `*.test.*` `*.spec.*` に該当するファイルの追加行は DB 検査（`HITS`）の対象から外す
- Terraform の `TF_DEL` とテスト削除検査（`test-guard-patterns.txt`）は従来どおり全 diff を見る
- `tests/hooks/run.sh` に「テストファイル内の `DROP TABLE` 文字列では deny しない」「マイグレーションの `DROP TABLE` では deny する」の 2 ケースを追加

### 3-2. `agent-complete.sh`: 起動直後の PostToolUse を「完了」と記録しない

`duration_seconds` が閾値（例 5 秒）未満なら `event=agent_spawned` として記録し、`post_context` のメッセージも「起動しました。完了は task-notification で通知されます」に変える。あるいは `SubagentStop` イベントが hooks.json で使えるならそちらで完了を取る。実際に完了したかは flow.log からは分からなくなるが、少なくとも誤った「完了」は消える。

### 3-3. 実バージョンの書き戻し STEP

implementation の最初の基盤グループ完了時（lock ファイル確定時）に、`composer.json` / `package.json` / lock から実バージョンを読み、`state.json.tech_stack` と要件定義書の技術スタック表を更新するタスクを checklist-writer が自動で入れる、または STEP H に組み込む。今回は compliance まで乖離が残り、人間判断が 1 回余分に要った。

### 3-4. pane 型ハングの根本原因

`SendFeedback` で Claude Code に報告済み。スキル側でできるのは検知と迂回まで。

### 3-5. worktree 作成時に依存物と `.env` を用意する

各 worktree は `vendor/` `node_modules/` `.env` を含まない（gitignore）。今回は Dev/QA の implementer が **グループごとに** `composer install` / `npm install` / `.env` 作成をやり直し、レビュアーも同じことをした（合計 10 回以上）。STEP A の `ensure_worktree` の直後に、メインの `vendor/` `node_modules/` をシンボリックリンクするかコピーし、`.env.example` から `.env` を生成する処理を入れれば、各エージェントの立ち上がりが数分縮む。ただし `node_modules` のシンボリックリンクは Vite / Vitest のパス解決で問題が出ることがあるので、コピー（`cp -R` or `rsync`）の方が安全。

### 3-6. スキャフォールドの不要物を基盤グループで除去する

`composer create-project laravel/laravel` は API 専用アプリに不要なものを大量に生成する（`routes/web.php` の welcome ビュー、`resources/views/welcome.blade.php`、`tests/Feature/ExampleTest.php` `tests/Unit/ExampleTest.php`、`backend/package.json` `backend/vite.config.js`、`resources/css` `resources/js`）。さらに **`backend/CLAUDE.md` と `backend/AGENTS.md`（Laravel Boost の案内）** が生成され、サブエージェントがこれを読むと「`composer require laravel/boost` を実行せよ」という指示に従いかねない（今回はオーケストレーターが無視したが、implementer に読ませていたら依存が増えていた）。compliance で「Blade ビューは使用しない」との乖離として検出され、人間判断が 1 回要った。

checklist-writer の CI 整備ルールと同じ位置に「新規プロジェクトセットアップ時は、要件定義書の技術スタック（API 専用 / Blade 不使用 等）に照らして**スキャフォールドの不要物を除去するタスク**を基盤グループに含める。生成された `CLAUDE.md` / `AGENTS.md` は削除するか、プロジェクトの規約に置き換える」を足す。

### 3-7. レビュアーの「実際に動かす」観点を手順化する

今回のレビュアー（特にグループ 5 の E2E）は自発的に「残留データありの状態で再実行」「Vite コールドスタートで再実行」まで行い、レース条件と strict mode violation を **実際に再現して** 報告した。これが無ければ PR マージ後の test ステージまで見つからなかった。一方、他のレビュアーは静的確認に留まったものもあった。

STEP D のレビュープロンプトに「テストを **実際に実行** する。可能なら (1) クリーンな状態、(2) 前回の残留データがある状態、(3) 依存サーバーの冷間起動、の 3 条件で回し、条件によって結果が変わるものを finding にする」を明記する。opus レビュアーの費用対効果はこの実行検証で最も出ている。

### 3-8. レビューの minor / info 指摘が消えている

memory 保存のルールは「同じ `rule` が 3 回以上」だが、今回は各グループ 1 回ずつなので何も保存されなかった。しかし `role="button"` の Space キー未対応、`aria-live` の常時マウント、`onClick={async}` の floating promise、`{n && <X />}` の 0 描画など、**汎用的で次のプロジェクトでも出る指摘**が minor として記録だけされ、次回に活きない。

`react.md` `laravel.md` 等の規約ファイルに「レビューで出た汎用指摘」を昇格させる経路を作る。案: STEP H で、そのグループの全レビュー findings のうち `rule` が `review/*`（規約に無かったもの）で汎用的なものを `doc/process/review-findings-backlog.md` に追記し、compliance の完了レポートで「規約ファイルへの昇格候補」として人間に提示する。

### 3-9. consistency の修正ループに上限と「重大のみ」の既定を置く

整合性チェックを 3 回回した（14 件 → 8 件 → 軽微 3 件）。毎回「全て修正する」を選んだが、サンプルアプリの規模では 2 回目以降の指摘は表記揺れ・粒度の問題が中心で、費用対効果は低かった。AskUserQuestion の選択肢は「全て修正 / 重要のみ / このまま進む」だったが、**2 周目以降は「重要のみ」を推奨（先頭に）** にし、3 周目で残っているものは自動的に「軽微として記録し進む」にする上限を `dev-flow-consistency/SKILL.md` に書く。

### 3-10. spec ステージの writer が `doc-validate` に 30 回以上弾かれていた

`flow.log` に `doc_invalid file=doc/test-spec/task-management-app.md` が 18:44〜19:03 の間に 30 件以上。test-spec-writer が同じ違反を繰り返し試行していた形跡。最終的には通ったが、hook のエラーメッセージが writer に十分伝わっていないか、writer が「何が違反か」を理解できずに書き直しを繰り返していた可能性がある。`doc-validate.py` の出力を確認し、違反箇所の行番号と「こう直せ」の具体例を含めるようにする。また writer のプロンプトに「hook のフィードバックで同じ違反が 3 回続いたら、修正方針を変えずに書き直すのをやめて `blocked` で報告する」を足す。

### 3-11. STEP H の機械的作業を hook かスクリプトにする

グループ完了ごとに「task_checklist.md のグループ N の `- [ ]` を `- [x]` に置換」「全一覧セクションの同じ項目も `[x]` に」「state.json の `completed_groups` に追加、`active_worktrees` から除去、`pr_numbers` に記録」「コミット」を手で行った（5 グループ分）。python3 の heredoc で毎回書いたが、内容は完全に機械的。`dev-flow/hooks/` に `mark-group-done.sh <N> <pr-numbers...>` のようなスクリプトを置いて STEP H から呼ぶ形にすれば、オーケストレーターのトークンも時間も減る。

### 3-12. Dev の完了 JSON の `confidence` / `needs_human_review` が使われていない

Dev/QA implementer は完了 JSON に `confidence` と `uncertainty_points` を書く設計で、`dev-flow/SKILL.md` STEP 5 に「confidence < 0.5 または needs_human_review=true なら人間ゲート」とある。しかし今回、implementer は自由テキストで報告し（fork で起動したため JSON フォーマットの指示が薄れた）、オーケストレーターも JSON をパースせず読み流した。`uncertainty_points` にあった「Laravel 13 になった」「is_completed の判定を独自実装した」等は、レビューで別途拾われたから良かったが、ゲートとしては機能していない。fork 起動時もプロンプト末尾の JSON フォーマット指示を落とさないこと、オーケストレーターが最低限 `needs_human_review` を確認すること、を `agent-hang-recovery.md` のフォールバック手順に追記する。

---

## 4. PR 作成依頼

### やってほしいこと

1. このリポジトリ（`~/dev-flow-skills`）の未コミット変更（§2 の 13 ファイル + 新規 1 ファイル + このファイル）を確認する。`git diff` で内容を読み、意図が §1〜2 と一致しているか見る
2. `bash tests/hooks/run.sh` が通ることを確認する（132 passed のはず）。`tests/check-conventions.py` があれば `testing.md` の変更（レビューチェックリストの列追加・ルール ID 追加）で壊れていないかも確認する
3. ブランチを切ってコミットする。分けるなら次の 4 つが自然：
   - ハング対策（`agent-hang-recovery.md` 新設 + 全ステージの `allowed-tools` + `dev-flow/SKILL.md` STEP 3.5）
   - **Dev / QA のテスト分担**（`testing.md` の分担表・Dev 向け書き方・チェックリスト担当列、`prompts/dev-*.md` `qa-*.md`、SKILL.md の STEP C/C.5/D の分担部分、checklist-writer の注記）← 設計変更なので単独コミットが望ましい
   - implementation の運用改善（STEP A の QA 無しグループ、STEP C.5 統合検証の骨格、STEP E OPEN、STEP G のマージ順序・deny 理由・UNKNOWN）
   - consistency / 注入の改善（checklist-writer の CI ルール・E2E 分担、`agent-prompt-injection.md` の環境ノート）
4. PR を作る。**このリポジトリの PR ルール**（ユーザーのグローバル CLAUDE.md より）:
   - タイトルは日本語
   - ラベル `claude` を付ける（無ければ作る）
   - アサインは `youmjww`
   - 説明は必ず書く。§1 の要約（どの詰まりにどう対処したか）と §3（未対応の提案）へのリンクを含める
   - **OPEN で作る**（Draft にしない。今回の修正自体が「スキル経由の PR は Draft にしない」と決めた内容）
   - 説明の末尾に `🤖 Generated with [Claude Code](https://claude.com/claude-code)` と Claude セッションのリンクを付ける（作業するセッションのものでよい）
5. §3 を対応するなら、その分は別ブランチ・別 PR にする（hook のテスト追加を伴うため）

### ブランチ名の案

`feat/retrospective-2026-09-22`（1 PR にまとめる場合）。分けるなら `feat/agent-hang-recovery` `feat/dev-qa-test-split` `feat/impl-ops-improvements` `feat/consistency-and-injection`

### PR タイトルの案

`実戦振り返り: pane 型ハングのフォールバック、Dev/QA テスト分担、implementation 運用の改善`

### 注意

- `~/.claude/skills/dev-flow*` はこのリポジトリへのシンボリックリンク。作業ツリーを変えると即座に有効になるので、ブランチ切替中に別セッションで `/dev-flow` を動かさないこと
- このファイル（`RETROSPECTIVE-2026-09-22.md`）は PR に含めてよい。リポジトリに振り返りの置き場（`docs/retrospectives/` 等）の慣習があればそこへ移動する
