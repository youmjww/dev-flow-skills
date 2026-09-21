package auth

import (
	"testing"
	"time"
)

// TC-001
func TestLogin_Success(t *testing.T) {
	clk := fakeClock{now: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)}
	got, err := Login(clk, "alice@example.com", "correct-horse")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Token == "" {
		t.Errorf("token should not be empty")
	}
}

// TC-002
func TestLogin_WrongPassword(t *testing.T) {
	tests := []struct {
		name string
		pw   string
		want error
	}{
		{name: "wrong", pw: "x", want: ErrInvalidCredentials},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Login(fakeClock{}, "alice@example.com", tt.pw)
			if err != tt.want {
				t.Errorf("got %v, want %v", err, tt.want)
			}
		})
	}
}
