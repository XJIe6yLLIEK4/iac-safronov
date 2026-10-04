#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-safronov-08}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

if yc load-balancer network-load-balancer get "$PREFIX-lb" >/dev/null 2>&1; then
  yc load-balancer network-load-balancer delete "$PREFIX-lb"
fi

if yc load-balancer target-group get "$PREFIX-tg" >/dev/null 2>&1; then
  yc load-balancer target-group delete "$PREFIX-tg"
fi

yc compute instance list --format json \
  | jq -r ".[] | select(.name | startswith(\"$PREFIX\")) | .name" \
  | while read -r name; do yc compute instance delete "$name"; done

if yc vpc subnet get "$PREFIX-subnet-a" >/dev/null 2>&1; then
  yc vpc subnet update --name "$PREFIX-subnet-a" --disassociate-route-table >/dev/null
fi

if yc vpc route-table get "$PREFIX-rt" >/dev/null 2>&1; then
  yc vpc route-table delete "$PREFIX-rt"
fi

if yc vpc gateway get "$PREFIX-nat" >/dev/null 2>&1; then
  yc vpc gateway delete "$PREFIX-nat"
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
