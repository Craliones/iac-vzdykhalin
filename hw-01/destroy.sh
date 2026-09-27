#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-vzdykhalin-09}"
OWNER="$PREFIX"

echo "==> балансировщики"

yc load-balancer network-load-balancer list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc load-balancer network-load-balancer delete "$name"
    done

echo "==> целевые группы"

yc load-balancer target-group list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc load-balancer target-group delete "$name"
    done

echo "==> виртуальные машины"

yc compute instance list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc compute instance delete "$name"
    done

echo "==> отвязка таблиц маршрутизации"

yc vpc subnet list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc vpc subnet update "$name" --disassociate-route-table
    done

echo "==> подсети"

yc vpc subnet list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc vpc subnet delete "$name"
    done

echo "==> таблицы маршрутизации"

yc vpc route-table list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc vpc route-table delete "$name"
    done

echo "==> NAT-шлюзы"

yc vpc gateway list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc vpc gateway delete "$name"
    done

echo "==> сети"

yc vpc network list --format json \
  | jq -r --arg owner "$OWNER" \
    '.[] | select(.labels.owner == $owner) | .name' \
  | while read -r name; do
      [[ -z "$name" ]] || yc vpc network delete "$name"
    done

echo "==> стенд удалён"
