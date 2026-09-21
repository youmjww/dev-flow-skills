---
doc_type: test-spec
covers: [REQ-001, REQ-002, REQ-003, REQ-004]
test_cases:
  - id: TC-001
    title: 正常系 正しい資格情報でログインできる
    covers: [REQ-001, REQ-003]
    implemented_by: pkg/auth/login_test.go::TestLogin_Success
  - id: TC-002
    title: 異常系 パスワード不一致で 401
    covers: [REQ-001]
    implemented_by: pkg/auth/login_test.go::TestLogin_WrongPassword
  - id: TC-003
    title: 異常系 5 回失敗でロック
    covers: [REQ-002]
  - id: TC-004
    title: 異常系 退会済みユーザーは 401
    covers: [REQ-004]
---

# テスト定義書: 認証

## 正常系テストケース

### TC-001: 正常系 正しい資格情報でログインできる
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

### TC-002: 異常系 パスワード不一致で 401
### TC-003: 異常系 5 回失敗でロック
### TC-004: 異常系 退会済みユーザーは 401
