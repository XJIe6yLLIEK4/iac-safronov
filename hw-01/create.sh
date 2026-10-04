#!/usr/bin/env bash
set -euo pipefail

# Аргумент командной строки важнее переменной окружения,
# переменная окружения важнее умолчания из варианта.
PREFIX="${PREFIX:-safronov-08}"
ZONE_A="${ZONE_A:-ru-central1-b}"
ZONE_B="${ZONE_B:-ru-central1-d}"
CIDR_A="${CIDR_A:-10.18.1.0/24}"
CIDR_B="${CIDR_B:-10.18.2.0/24}"
APP_PORT="${APP_PORT:-8024}"
GREETING="${GREETING:-labwork}"
WEB_COUNT="${WEB_COUNT:-3}"
ENV_NAME="${ENV_NAME:-stage}"
BOOT_SIZE="${BOOT_SIZE:-20}"
IMAGE_FAMILY="${IMAGE_FAMILY:-ubuntu-2404-lts}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --zone-a) ZONE_A="$2"; shift 2 ;;
    --zone-b) ZONE_B="$2"; shift 2 ;;
    --cidr-a) CIDR_A="$2"; shift 2 ;;
    --cidr-b) CIDR_B="$2"; shift 2 ;;
    --app-port) APP_PORT="$2"; shift 2 ;;
    --greeting) GREETING="$2"; shift 2 ;;
    --web-count) WEB_COUNT="$2"; shift 2 ;;
    --env-name) ENV_NAME="$2"; shift 2 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

echo "==> окружение $ENV_NAME"

echo "==> сеть"
if yc vpc network get "$PREFIX-net" >/dev/null 2>&1; then
  echo "сеть $PREFIX-net уже есть, пропускаю"
else
  yc vpc network create --name "$PREFIX-net"
fi

echo "==> подсети"
if yc vpc subnet get "$PREFIX-subnet-a" >/dev/null 2>&1; then
  echo "подсеть $PREFIX-subnet-a уже есть, пропускаю"
else
  yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
    --zone "$ZONE_A" --range "$CIDR_A"
fi

if yc vpc subnet get "$PREFIX-subnet-b" >/dev/null 2>&1; then
  echo "подсеть $PREFIX-subnet-b уже есть, пропускаю"
else
  yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
    --zone "$ZONE_B" --range "$CIDR_B"
fi

echo "==> NAT-шлюз и таблица маршрутизации"
if yc vpc gateway get "$PREFIX-nat" >/dev/null 2>&1; then
  echo "шлюз $PREFIX-nat уже есть, пропускаю"
else
  yc vpc gateway create --name "$PREFIX-nat"
fi

GW_ID=$(yc vpc gateway get --name "$PREFIX-nat" --format json | jq -r .id)
if yc vpc route-table get "$PREFIX-rt" >/dev/null 2>&1; then
  echo "таблица $PREFIX-rt уже есть, пропускаю"
else
  yc vpc route-table create --name "$PREFIX-rt" --network-name "$PREFIX-net" \
    --route "destination=0.0.0.0/0,gateway-id=$GW_ID"
fi
yc vpc subnet update --name "$PREFIX-subnet-a" --route-table-name "$PREFIX-rt" >/dev/null

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < hw-01/cloud-init.tpl.yaml > hw-01/cloud-init-app.yaml

echo "==> сервер приложения"
if yc compute instance get "$PREFIX-app" >/dev/null 2>&1; then
  echo "машина $PREFIX-app уже есть, пропускаю"
else
  yc compute instance create \
    --name "$PREFIX-app" \
    --zone "$ZONE_A" \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="$PREFIX-subnet-a" \
    --hostname "$PREFIX-app" \
    --metadata-from-file user-data=hw-01/cloud-init-app.yaml
fi

APP_IP=$(yc compute instance get "$PREFIX-app" --format json \
  | jq -r '.network_interfaces[0].primary_v4_address.address')
export APP_IP
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY} ${APP_IP}' \
  < hw-01/cloud-init-web.tpl.yaml > hw-01/cloud-init-web.yaml

echo "==> веб-серверы"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")
for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  if yc compute instance get "$PREFIX-web-$i" >/dev/null 2>&1; then
    echo "машина $PREFIX-web-$i уже есть, пропускаю"
  else
    yc compute instance create \
      --name "$PREFIX-web-$i" \
      --zone "${ZONES[$idx]}" \
      --platform standard-v3 \
      --cores=2 --core-fraction=20 --memory=2 \
      --preemptible \
      --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
      --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4 \
      --hostname "$PREFIX-web-$i" \
      --metadata-from-file user-data=hw-01/cloud-init-web.yaml
  fi
done

echo "==> целевая группа"
TARGETS=""
for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-web-$i" --format json \
    | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
done

if yc load-balancer target-group get "$PREFIX-tg" >/dev/null 2>&1; then
  echo "целевая группа $PREFIX-tg уже есть, пропускаю"
else
  yc load-balancer target-group create --name "$PREFIX-tg" $TARGETS
fi

echo "==> балансировщик"
if yc load-balancer network-load-balancer get "$PREFIX-lb" >/dev/null 2>&1; then
  echo "балансировщик $PREFIX-lb уже есть, пропускаю"
else
  TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
  yc load-balancer network-load-balancer create \
    --name "$PREFIX-lb" \
    --region-id ru-central1 \
    --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
    --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/
fi

echo "==> ожидание готовности"
for attempt in $(seq 1 60); do
  if WEB_COUNT="$WEB_COUNT" bash hw-01/check.sh >/dev/null 2>&1; then
    echo "стенд готов"
    exit 0
  fi
  sleep 10
done

echo "стенд не стал готов за отведённое время" >&2
exit 1
