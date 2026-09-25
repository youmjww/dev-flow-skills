#!/bin/bash
# 違反例: 復元が trap に無い / WARN で流す / grep -c / IPv4 限定 / 自己比較 / sleep
systemctl stop nginx
sleep 5
expected="$(nginx -v 2>&1)"
actual="$expected"
[ "$actual" = "$actual" ] && echo ok
n="$(grep -c 'server ' /etc/nginx/conf.d/upstream.conf)"
grep -Eq '^allow [0-9]{1,3}\.[0-9]{1,3}' /etc/nginx/conf.d/allow.conf
systemctl start nginx || echo "WARN: 復元に失敗"
