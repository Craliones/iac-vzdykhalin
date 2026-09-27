#!/usr/bin/env bash
set -euo pipefail

# ---------- параметры варианта ----------
PREFIX="${PREFIX:-vzdykhalin-09}"
ZONE_A="${ZONE_A:-ru-central1-d}"
ZONE_B="${ZONE_B:-ru-central1-a}"
CIDR_A="${CIDR_A:-10.19.1.0/24}"
CIDR_B="${CIDR_B:-10.19.2.0/24}"
APP_PORT="${APP_PORT:-8027}"
GREETING="${GREETING:-cloudlab}"
WEB_COUNT="${WEB_COUNT:-2}"
ENV_NAME="${ENV_NAME:-lab}"

BOOT_SIZE="${BOOT_SIZE:-25}"
IMAGE_FAMILY="${IMAGE_FAMILY:-ubuntu-2404-lts}"

# ---------- аргументы командной строки ----------
# Аргумент важнее переменной окружения, переменная окружения важнее значения по умолчанию.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --web-count)
      WEB_COUNT="$2"
      shift 2
      ;;
    --port)
      APP_PORT="$2"
      shift 2
      ;;
    --greeting)
      GREETING="$2"
      shift 2
      ;;
    --env)
      ENV_NAME="$2"
      shift 2
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      exit 2
      ;;
  esac
done

if ! [[ "$WEB_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "WEB_COUNT должен быть положительным целым числом"
  exit 2
fi

LABELS="env=$ENV_NAME,owner=$PREFIX"

ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")

echo "==> параметры"
echo "PREFIX=$PREFIX"
echo "WEB_COUNT=$WEB_COUNT"
echo "APP_PORT=$APP_PORT"
echo "GREETING=$GREETING"
echo "ENV_NAME=$ENV_NAME"

# ---------- сеть ----------
echo "==> сеть"

if yc vpc network get "$PREFIX-net" >/dev/null 2>&1; then
  echo "сеть $PREFIX-net уже существует, пропускаю"
else
  yc vpc network create \
    --name "$PREFIX-net" \
    --labels "$LABELS"
fi

# ---------- подсети ----------
echo "==> подсети"

if yc vpc subnet get "$PREFIX-subnet-a" >/dev/null 2>&1; then
  echo "подсеть $PREFIX-subnet-a уже существует, пропускаю"
else
  yc vpc subnet create \
    --name "$PREFIX-subnet-a" \
    --network-name "$PREFIX-net" \
    --zone "$ZONE_A" \
    --range "$CIDR_A" \
    --labels "$LABELS"
fi

if yc vpc subnet get "$PREFIX-subnet-b" >/dev/null 2>&1; then
  echo "подсеть $PREFIX-subnet-b уже существует, пропускаю"
else
  yc vpc subnet create \
    --name "$PREFIX-subnet-b" \
    --network-name "$PREFIX-net" \
    --zone "$ZONE_B" \
    --range "$CIDR_B" \
    --labels "$LABELS"
fi

# ---------- NAT-шлюз ----------
echo "==> NAT-шлюз"

if yc vpc gateway get "$PREFIX-nat" >/dev/null 2>&1; then
  echo "NAT-шлюз $PREFIX-nat уже существует, пропускаю"
else
  yc vpc gateway create \
    --name "$PREFIX-nat" \
    --labels "$LABELS"
fi

GW_ID=$(yc vpc gateway get "$PREFIX-nat" --format json | jq -r '.id')

# ---------- таблица маршрутизации ----------
echo "==> таблица маршрутизации"

if yc vpc route-table get "$PREFIX-rt" >/dev/null 2>&1; then
  echo "таблица $PREFIX-rt уже существует, пропускаю"
else
  yc vpc route-table create \
    --name "$PREFIX-rt" \
    --network-name "$PREFIX-net" \
    --route "destination=0.0.0.0/0,gateway-id=$GW_ID" \
    --labels "$LABELS"
fi

# Сервер приложения находится в subnet-a и получает выход в интернет через NAT.
yc vpc subnet update \
  --name "$PREFIX-subnet-a" \
  --route-table-name "$PREFIX-rt"

# ---------- cloud-init ----------
echo "==> cloud-init"

SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY

envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < hw-01/cloud-init.tpl.yaml \
  > hw-01/cloud-init.yaml

# ---------- веб-серверы ----------
echo "==> веб-серверы"

for i in $(seq 1 "$WEB_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  NAME="$PREFIX-web-$i"

  if yc compute instance get "$NAME" >/dev/null 2>&1; then
    echo "ВМ $NAME уже существует, пропускаю"
    continue
  fi

  yc compute instance create \
    --name "$NAME" \
    --zone "${ZONES[$idx]}" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4 \
    --hostname "$NAME" \
    --metadata-from-file user-data=hw-01/cloud-init.yaml \
    --labels "$LABELS"
done

# ---------- сервер приложения ----------
echo "==> сервер приложения"

if yc compute instance get "$PREFIX-app-1" >/dev/null 2>&1; then
  echo "ВМ $PREFIX-app-1 уже существует, пропускаю"
else
  yc compute instance create \
    --name "$PREFIX-app-1" \
    --zone "$ZONE_A" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="$PREFIX-subnet-a" \
    --hostname "$PREFIX-app-1" \
    --metadata-from-file user-data=hw-01/cloud-init.yaml \
    --labels "$LABELS"
fi

# ---------- целевая группа ----------
echo "==> целевая группа"

if yc load-balancer target-group get "$PREFIX-tg" >/dev/null 2>&1; then
  echo "целевая группа $PREFIX-tg уже существует, пропускаю"
else
  TARGETS=""

  for i in $(seq 1 "$WEB_COUNT"); do
    idx=$(( (i - 1) % 2 ))

    IP=$(yc compute instance get "$PREFIX-web-$i" --format json \
      | jq -r '.network_interfaces[0].primary_v4_address.address')

    TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
  done

  yc load-balancer target-group create \
    --name "$PREFIX-tg" \
    --labels "$LABELS" \
    $TARGETS
fi

# ---------- балансировщик ----------
echo "==> балансировщик"

if yc load-balancer network-load-balancer get "$PREFIX-lb" >/dev/null 2>&1; then
  echo "балансировщик $PREFIX-lb уже существует, пропускаю"
else
  TG_ID=$(yc load-balancer target-group get "$PREFIX-tg" \
    --format json | jq -r '.id')

  yc load-balancer network-load-balancer create \
    --name "$PREFIX-lb" \
    --region-id ru-central1 \
    --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
    --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/ \
    --labels "$LABELS"
fi

echo "==> стенд создан"


