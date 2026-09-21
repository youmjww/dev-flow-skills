---
doc_type: test-spec
covers: [REQ-001, REQ-002, REQ-003, REQ-004]
test_cases:
  - id: TC-001
    title: 正常系: 正しい資格情報でログインできる
    covers: [REQ-001, REQ-003]
    implemented_by: pkg/auth/login_test.go::TestLogin_Success
  - id: TC-002
    title: 異常系: パスワード不一致で 401
    covers: [REQ-001]
    implemented_by: pkg/auth/login_test.go::TestLogin_WrongPassword
  - id: TC-003
    title: 異常系: 5 回失敗でロック
    covers: [REQ-002]
  - id: TC-004
    title: 異常系: 退会済みユーザーは 401
    covers: [REQ-004]
---

# テスト定義書: 認証

## 正常系テストケース

### TC-001: 正常系: 正しい資格情報でログインできる
**対象要件**: REQ-001, REQ-003
**API**: API-001

```gherkin
Feature: ログイン
  Scenario: 正しい資格情報
    Given ユーザー alice@example.com がパスワード "correct-horse" で登録されている
    When POST /auth/login に {"email":"alice@example.com","password":"correct-horse"} を送る
    Then HTTP 200 が返る
    And body.token は HS256 の JWT で exp が発行時刻 + 86400 秒である
```

**具体的な入出力値:**
- 入力: `{"email":"alice@example.com","password":"correct-horse"}`
- 期待出力: `{"token":"<JWT>"}`

## 異常系テストケース

### TC-002: 異常系: パスワード不一致で 401
**対象要件**: REQ-001
**API**: API-001

```gherkin
Feature: ログイン
  Scenario: パスワード不一致
    Given ユーザー alice@example.com がパスワード "correct-horse" で登録されている
    When POST /auth/login に {"email":"alice@example.com","password":"wrong"} を送る
    Then HTTP 401 が返る
    And body.error.code は "INVALID_CREDENTIALS" である
```

**具体的な入出力値:**
- 入力: `{"email":"alice@example.com","password":"wrong"}`
- 期待出力: `{"error":{"code":"INVALID_CREDENTIALS"}}`

### TC-003: 異常系: 5 回失敗でロック
**対象要件**: REQ-002
**API**: API-001

```gherkin
Feature: ログイン
  Scenario: 5 回連続失敗でロック
    Given ユーザー bob@example.com がパスワード "correct-horse" で登録されている
    And 直前に誤ったパスワードで 5 回連続でログインに失敗している
    When POST /auth/login に {"email":"bob@example.com","password":"correct-horse"} を送る
    Then HTTP 423 が返る
    And body.error.code は "ACCOUNT_LOCKED" である
```

**具体的な入出力値:**
- 入力: 誤パスワード `{"email":"bob@example.com","password":"x"}` × 5 回 → 正パスワード `{"email":"bob@example.com","password":"correct-horse"}`
- 期待出力: 5 回目まで `401 INVALID_CREDENTIALS`、6 回目 `423 {"error":{"code":"ACCOUNT_LOCKED"}}`

### TC-004: 異常系: 退会済みユーザーは 401
**対象要件**: REQ-004
**API**: API-001

```gherkin
Feature: ログイン
  Scenario: 退会済みユーザー
    Given ユーザー carol@example.com がパスワード "correct-horse" で登録され、deleted_at が 2026-01-01T00:00:00Z である
    When POST /auth/login に {"email":"carol@example.com","password":"correct-horse"} を送る
    Then HTTP 401 が返る
    And body.error.code は "INVALID_CREDENTIALS" である（退会の事実を漏らさない）
```

**具体的な入出力値:**
- 入力: `{"email":"carol@example.com","password":"correct-horse"}`
- 期待出力: `{"error":{"code":"INVALID_CREDENTIALS"}}`
