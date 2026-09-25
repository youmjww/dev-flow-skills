#!/bin/bash
# TC-068: nginx 停止時に 502 を返し、終了時に必ず復元する
set -euo pipefail

restore() { systemctl start nginx; }
trap restore EXIT

systemctl stop nginx
code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/)"
[ "$code" = "502" ] || { echo "FAIL: expected 502, got $code"; exit 1; }

# 出現回数は grep -o | wc -l で数える
n="$(grep -o 'server ' /etc/nginx/conf.d/upstream.conf | wc -l)"
[ "$n" -eq 2 ] || { echo "FAIL: upstream count $n"; exit 1; }

# IPv4 射影 IPv6（::ffff:）も許可する
grep -Eq '^allow (::ffff:)?[0-9]{1,3}\.[0-9]{1,3}' /etc/nginx/conf.d/allow.conf
