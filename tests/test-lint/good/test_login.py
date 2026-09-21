import pytest
from freezegun import freeze_time

from app.auth import login, InvalidCredentials


# TC-001
@freeze_time("2026-01-01")
def test_login_success_returns_token():
    token = login("alice@example.com", "correct-horse")
    assert token.startswith("eyJ")


# TC-002
@pytest.mark.parametrize("pw", ["x", ""], ids=["wrong", "empty"])
def test_login_wrong_password_raises(pw):
    with pytest.raises(InvalidCredentials):
        login("alice@example.com", pw)
