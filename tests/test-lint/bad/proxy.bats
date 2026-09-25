#!/usr/bin/env bats

@test "TC-001 スキップ" {
  skip "あとで"
  [ 1 -eq 1 ]
}

@test "TC-002 assert なし" {
  curl -s http://localhost/health
}

@test "TC-003 空" {
}
