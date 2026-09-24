#!/bin/bash
set -e

PREFIX=vzdykhalin-09
ZONE=ru-central1-d
CIDR=10.19.1.0/24
DISK_SIZE=25
IMAGE_FAMILY=debian-12
PORT=8027
WORD=cloudlab
yc vpc network create --name "$PREFIX-net"

yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"
for i in 1 2; do
  yc compute instance create \
    --name "$PREFIX-app-$i" \
    --zone "$ZONE" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$DISK_SIZE" \
    --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
    --ssh-key ~/.ssh/id_ed25519.pub \
    --labels created-by=script
done
