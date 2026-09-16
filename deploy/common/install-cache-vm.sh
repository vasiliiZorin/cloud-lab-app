#!/usr/bin/env bash
# Provisions a bare Ubuntu 22.04/24.04 VM to run the cache tier: installs
# Redis, sets a password, and binds it to the private network interface.
#
# Usage: PRIVATE_IP=10.0.1.20 REDIS_PASSWORD=... ./install-cache-vm.sh
set -euo pipefail

PRIVATE_IP="${PRIVATE_IP:?set PRIVATE_IP to this VM's private IP}"
REDIS_PASSWORD="${REDIS_PASSWORD:?set REDIS_PASSWORD}"

apt-get update -y
apt-get install -y redis-server

sed -i "s/^bind .*/bind 127.0.0.1 ${PRIVATE_IP}/" /etc/redis/redis.conf
sed -i "s/^# requirepass .*/requirepass ${REDIS_PASSWORD}/" /etc/redis/redis.conf
sed -i "s/^protected-mode .*/protected-mode yes/" /etc/redis/redis.conf

systemctl restart redis-server

echo "Redis ready on ${PRIVATE_IP}:6379. Also lock this down at the network layer:"
echo "  - security group / NSG: allow tcp/6379 from the app tier's CIDR only, deny 0.0.0.0/0"
