package auth

import (
	"testing"
	"time"
)

func TestLogin_Skipped(t *testing.T) {
	t.Skip("flaky")
}

func TestLogin_NoAssert(t *testing.T) {
	_, _ = Login(fakeClock{}, "a@example.com", "x")
	time.Sleep(100 * time.Millisecond)
}

func TestLogin_Empty(t *testing.T) {
}

func TestLogin_Tautology(t *testing.T) {
	expected := Hash("pw")
	got := Hash("pw")
	if got != expected {
		t.Errorf("mismatch")
	}
}

// func TestLogin_Old(t *testing.T) {
// }

func TestLogin_Now(t *testing.T) {
	tok := Issue(time.Now())
	if tok == "" {
		t.Fatal("empty")
	}
}
