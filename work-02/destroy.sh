#!/usr/bin/env bash
set -euo pipefail            # стоп на первой ошибке и на пустой переменной

PREFIX=safronov-08            # у вас — свои значения из варианта
if yc load-balancer network-load-balancer get "$PREFIX-lb" >/dev/null 2>&1; then
  yc load-balancer network-load-balancer delete "$PREFIX-lb"
fi

if yc load-balancer target-group get "$PREFIX-tg" >/dev/null 2>&1; then
  yc load-balancer target-group delete "$PREFIX-tg"
fi

for name in $(yc compute instance list --format json \
  | jq -r '.[].name' \
  | grep "^$PREFIX-app-" || true); do
  yc compute instance delete "$name"
done

if yc compute disk get "$PREFIX-data" >/dev/null 2>&1; then
  yc compute disk delete "$PREFIX-data"
fi

if yc vpc subnet get "$PREFIX-subnet-a" >/dev/null 2>&1; then
  yc vpc subnet delete "$PREFIX-subnet-a"
fi

if yc vpc subnet get "$PREFIX-subnet-b" >/dev/null 2>&1; then
  yc vpc subnet delete "$PREFIX-subnet-b"
fi

if yc vpc network get "$PREFIX-net" >/dev/null 2>&1; then
  yc vpc network delete "$PREFIX-net"
fi
