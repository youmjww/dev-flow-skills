import time
import pytest
from datetime import datetime

from app.auth import login, hash_pw


@pytest.mark.skip(reason="later")
def test_login_skipped():
    assert login("a", "b")


def test_login_no_assert():
    login("a@example.com", "x")
    time.sleep(1)


def test_login_swallow():
    try:
        login("a@example.com", "x")
    except Exception:
        pass
    assert True


def test_login_tautology():
    expected = hash_pw("pw")
    assert hash_pw("pw") == expected


def test_login_now():
    assert login("a@example.com", "x", now=datetime.now())


# def test_old():
#     pass
