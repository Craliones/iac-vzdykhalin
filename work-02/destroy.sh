#!/usr/bin/env bash
set -euo pipefail

PREFIX=vzdykhalin-09

echo "==> балансировщик"

if yc load-balancer network-load-balancer get "$PREFIX-lb" >/dev/null 2>&1; then
  yc load-balancer network-load-balancer delete "$PREFIX-lb"
fi

echo "==> целевая группа"

if yc load-balancer target-group get "$PREFIX-tg" >/dev/null 2>&1; then
  yc load-balancer target-group delete "$PREFIX-tg"
fi

echo "==> машины"

VM_NAMES=$(yc compute instance list --format json \
  | jq -r --arg prefix "$PREFIX-app-" \
  '.[] | select(.name | startswith($prefix)) | .name')

for name in $VM_NAMES; do
  yc compute instance delete "$name"
done

echo "==> дополнительный диск"

if yc compute disk get "$PREFIX-data" >/dev/null 2>&1; then
  yc compute disk delete "$PREFIX-data"
fi

echo "==> подсети"

if yc vpc subnet get "$PREFIX-subnet-a" >/dev/null 2>&1; then
  yc vpc subnet delete "$PREFIX-subnet-a"
fi

if yc vpc subnet get "$PREFIX-subnet-b" >/dev/null 2>&1; then
  yc vpc subnet delete "$PREFIX-subnet-b"
fi

echo "==> сеть"

if yc vpc network get "$PREFIX-net" >/dev/null 2>&1; then
  yc vpc network delete "$PREFIX-net"
fi
