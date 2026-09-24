#!/bin/bash
set -e

PREFIX=vzdykhalin-09

for i in 1 2; do
  yc compute instance delete "$PREFIX-app-$i"
done

yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"
