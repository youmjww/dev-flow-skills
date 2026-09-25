#!/usr/bin/env bats

teardown() {
  systemctl start nginx
}

@test "TC-001 正常系: /health が 200 を返す" {
  run curl -s -o /dev/null -w '%{http_code}' http://localhost/health
  [ "$status" -eq 0 ]
  [ "$output" = "200" ]
}

@test "TC-002 異常系: nginx 停止中は接続できない" {
  systemctl stop nginx
  run curl -s http://localhost/health
  [ "$status" -ne 0 ]
}
