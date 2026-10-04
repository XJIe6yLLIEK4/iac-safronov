#!/usr/bin/env bash
set -uo pipefail

PREFIX="${PREFIX:-safronov-08}"
APP_PORT="${APP_PORT:-8024}"
WEB_COUNT="${WEB_COUNT:-3}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --app-port) APP_PORT="$2"; shift 2 ;;
    --web-count) WEB_COUNT="$2"; shift 2 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

STATUS=0

if ! yc load-balancer network-load-balancer get "$PREFIX-lb" >/dev/null 2>&1; then
  echo "✗ балансировщик $PREFIX-lb не найден"
  echo "✗ ответы машин получить нельзя"
  echo "✗ сервер приложения проверить нельзя"
  exit 1
fi

LB_IP=$(yc load-balancer network-load-balancer get "$PREFIX-lb" --format json \
  | jq -r '.listeners[0].address')
HTTP_CODE=$(curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' "http://$LB_IP" || true)

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✓ балансировщик отвечает: 200"
else
  echo "✗ балансировщик отвечает: $HTTP_CODE"
  STATUS=1
fi

RESPONSES=$(for i in $(seq 1 12); do curl -s --connect-timeout 3 --max-time 5 "http://$LB_IP" || true; echo; done)
MACHINES=$(printf '%s\n' "$RESPONSES" | awk '/ on / {print $3}' | sort -u)
MACHINE_COUNT=$(printf '%s\n' "$MACHINES" | awk 'NF {count++} END {print count+0}')
MACHINE_LIST=$(printf '%s\n' "$MACHINES" | paste -sd ',' - | sed 's/,/, /g')

if [[ "$MACHINE_COUNT" -eq "$WEB_COUNT" ]]; then
  echo "✓ ответили машины: $MACHINE_LIST"
else
  echo "✗ ответили не все машины: $MACHINE_LIST"
  STATUS=1
fi

APP_CODE=$(curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code}' "http://$LB_IP/app-health" || true)

if [[ "$APP_CODE" == "200" ]]; then
  echo "✓ сервер приложения доступен с $PREFIX-web-1"
else
  echo "✗ сервер приложения недоступен с $PREFIX-web-1"
  STATUS=1
fi

exit "$STATUS"
