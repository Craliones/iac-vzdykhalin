#!/usr/bin/env bash
set -u

PREFIX="${PREFIX:-vzdykhalin-09}"
APP_PORT="${APP_PORT:-8027}"
GREETING="${GREETING:-cloudlab}"

RESULT=0

# ---------- балансировщик ----------
LB_IP=$(yc load-balancer network-load-balancer get "$PREFIX-lb" \
  --format json 2>/dev/null | jq -r '.listeners[0].address // empty')

if [[ -z "$LB_IP" ]]; then
  echo "✗ балансировщик не найден"
  exit 1
fi

HTTP_CODE=$(curl \
  --retry 5 \
  --retry-delay 2 \
  --retry-all-errors \
  --max-time 5 \
  -s \
  -o /dev/null \
  -w '%{http_code}' \
  "http://$LB_IP" || true)

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✓ балансировщик отвечает: 200"
else
  echo "✗ балансировщик отвечает: $HTTP_CODE"
  RESULT=1
fi

# ---------- распределение между веб-серверами ----------
RESPONSES=""

for i in $(seq 1 10); do
  ANSWER=$(curl --max-time 5 -s "http://$LB_IP" || true)

  HOST=$(echo "$ANSWER" \
    | grep -o "$PREFIX-web-[0-9]*" \
    | head -n 1 || true)

  if [[ -n "$HOST" ]]; then
    RESPONSES="$RESPONSES"$'\n'"$HOST"
  fi
done

UNIQUE_HOSTS=$(echo "$RESPONSES" | sed '/^$/d' | sort -u)
HOST_COUNT=$(echo "$UNIQUE_HOSTS" | sed '/^$/d' | wc -l)

if [[ "$HOST_COUNT" -gt 1 ]]; then
  echo "✓ ответили машины: $(echo "$UNIQUE_HOSTS" | tr '\n' ' ')"
else
  echo "✗ ответила только одна машина: $(echo "$UNIQUE_HOSTS" | tr '\n' ' ')"
  RESULT=1
fi

# ---------- сервер приложения ----------
APP_INTERNAL_IP=$(yc compute instance get "$PREFIX-app-1" \
  --format json 2>/dev/null \
  | jq -r '.network_interfaces[0].primary_v4_address.address // empty')

APP_OK=0
APP_CHECK_FROM=""

if [[ -n "$APP_INTERNAL_IP" ]]; then
  for i in 1 2; do
    WEB_IP=$(yc compute instance get "$PREFIX-web-$i" \
      --format json 2>/dev/null \
      | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address // empty')

    if [[ -z "$WEB_IP" ]]; then
      continue
    fi

    APP_RESPONSE=$(ssh \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=accept-new \
      -o IdentitiesOnly=yes \
      -i ~/.ssh/id_ed25519 \
      student@"$WEB_IP" \
      "curl --max-time 5 -s http://$APP_INTERNAL_IP:$APP_PORT" \
      2>/dev/null || true)

    if echo "$APP_RESPONSE" | grep -q "$GREETING on $PREFIX-app-1"; then
      APP_OK=1
      APP_CHECK_FROM="$PREFIX-web-$i"
      break
    fi
  done
fi

if [[ "$APP_OK" -eq 1 ]]; then
  echo "✓ сервер приложения доступен с $APP_CHECK_FROM"
else
  echo "✗ сервер приложения недоступен с веб-серверов"
  RESULT=1
fi
exit "$RESULT"
