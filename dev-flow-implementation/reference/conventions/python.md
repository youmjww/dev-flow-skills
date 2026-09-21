# Python

## 書き方（implementer 向け）

### 命名・構成
- PEP 8。モジュール・関数・変数は `snake_case`、クラスは `PascalCase`、定数は `UPPER_SNAKE`。1 文字変数はループ変数以外で使わない
- `src/` レイアウト（`src/<package>/`）+ `tests/` を基本にする。`__init__.py` に処理を書かない
- 公開 API は `__all__` で明示するか、内部用は先頭 `_` を付ける
- 型ヒントを**すべての関数シグネチャ**に付ける（引数・戻り値）。`Any` は JSON の動的部分など理由がある場合のみで、コメントで理由を書く
- データの入れ物は `@dataclass(frozen=True)` か Pydantic モデル。`dict` を構造体代わりに引き回さない
- 標準ライブラリを優先する（`pathlib` > `os.path`、`datetime` は必ず `tzinfo` 付き、`logging` > `print`）

### エラー処理
- `except Exception:` / 裸の `except:` で握りつぶさない。捕まえる例外を特定し、処理できないなら `raise` で再送出（`raise ... from e` で原因を保つ）
- 独自例外はモジュールごとに基底クラス（`class AppError(Exception)`）を作り、そこから派生させる
- エラーを戻り値（`None` / `False` / `-1`）で表現しない。例外を使う。`Optional` を返すのは「無いことが正常」な場合だけ
- ログは `logger = logging.getLogger(__name__)`。例外のログは `logger.exception()` でスタックトレースを残す
- `assert` を入力検証に使わない（`-O` で消える）

### 並行処理・非同期
- `async def` の中で同期 I/O（`requests`、`time.sleep`、同期 DB）を呼ばない。`httpx.AsyncClient` / `asyncio.sleep` / 非同期ドライバを使う
- `asyncio.create_task` した Task は参照を保持し、例外を回収する（`gather` / `TaskGroup`）。放置すると例外が消える
- CPU バウンドは `ProcessPoolExecutor`、GIL を意識する。スレッドで CPU 並列を期待しない
- 共有可変状態を避ける。必要なら `asyncio.Lock` / `threading.Lock`

### 依存・境界
- 外部 I/O（DB・HTTP・時計）はクラスや関数の引数で注入し、テストで差し替える。`datetime.now()` の直接呼び出しを避ける
- モジュールの import 時に副作用（接続・ファイル読み込み）を起こさない
- 依存は `pyproject.toml` に宣言し、バージョンをロック（`uv.lock` / `poetry.lock` / `requirements.txt` の pin）
- 可変デフォルト引数（`def f(x=[])`）を使わない。`None` にして中で初期化

### テスト
- `pytest`。テスト関数は `test_<対象>_<条件>_<期待>`（`test_login_wrong_password_returns_401`）。TC-ID をコメントで対応付ける
- 複数ケースは `@pytest.mark.parametrize`。ケースごとに `id=` を付けて失敗時に読めるようにする
- フィクスチャは `conftest.py`。スコープは最小（`function`）を基本にし、DB 接続など重いものだけ `session`
- モックは境界（HTTP・DB・時計）だけ。自分のモジュール内部を `patch` し始めたら設計を疑う
- `pytest --strict-markers` と `-W error`（警告をエラー扱い）を CI で有効にする

## レビューチェックリスト（reviewer 向け）

| ルール ID | 重大度 | 確認内容 | 確認方法 |
|---|---|---|---|
| `py/sql-injection` | blocker | SQL を f-string / `%` / `+` で組み立てていない（プレースホルダを使う） | `grep -nE 'f".*(SELECT|INSERT|UPDATE|DELETE)|execute\(.*%'` |
| `py/secrets-hardcoded` | blocker | トークン・パスワード・鍵がソースに無い | `grep -niE '(password|secret|token|api_key)\s*=\s*["\x27][^"\x27]+'` |
| `py/authz-missing` | blocker | 認可が必要なエンドポイントで権限チェックが抜けていない | ルートごとに要件定義書と照合 |
| `py/eval-exec` | blocker | `eval` / `exec` / `pickle.loads` / `yaml.load`（`safe_load` 以外）を外部入力に使っていない | `grep -nE '\b(eval|exec|pickle\.loads|yaml\.load)\('` |
| `py/bare-except` | major | 裸の `except:` / `except Exception: pass` が無い | `grep -nE 'except(\s*Exception)?\s*:'` の直後 |
| `py/exception-chain` | major | 再送出が `raise X from e` で原因を保っている | `raise` の周辺 |
| `py/type-hints` | major | 公開関数に型ヒントがあり、`mypy` / `pyright` が通る | 実行して確認 |
| `py/sync-in-async` | major | `async def` 内で同期 I/O を呼んでいない | `grep -nE 'requests\.|time\.sleep' ` が async 関数内 |
| `py/task-unawaited` | major | `create_task` の結果が回収されている | `grep -n 'create_task'` |
| `py/mutable-default` | major | 可変デフォルト引数が無い | `grep -nE 'def .*=\s*(\[\]|\{\})'` |
| `py/naive-datetime` | major | `datetime.now()` / `utcnow()` を tz なしで使っていない | `grep -nE 'datetime\.(now\(\)|utcnow)'` |
| `py/return-none-as-error` | major | エラーを `None` / `False` の戻り値で表現していない | 呼び出し側が `if result is None` でエラー分岐している箇所 |
| `py/parametrize` | minor | 複数ケースのテストが `parametrize` になっている | テストの構造 |
| `py/pathlib` | minor | `os.path` より `pathlib` | `grep -n 'os.path'` |
| `py/print-logging` | minor | ライブラリ・サービスコードで `print` を使っていない | `grep -n 'print('` |

## 標準コマンド（tech_stack が空のときのフォールバック）

| 用途 | コマンド |
|---|---|
| format | `ruff format --check .` |
| lint | `ruff check .` |
| 型検査 | `mypy .`（または `pyright`） |
| test | `pytest -q -W error` |
