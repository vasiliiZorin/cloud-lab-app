#!/usr/bin/env bash
# Provisions a bare Ubuntu 22.04/24.04 VM to run the database tier:
# installs PostgreSQL, creates the app role/database, loads the schema,
# and opens it to connections from the app-tier's private IP only.
#
# Usage: APP_TIER_CIDR=10.0.0.0/24 DB_PASSWORD=... ./install-db-vm.sh
set -euo pipefail

APP_TIER_CIDR="${APP_TIER_CIDR:?set APP_TIER_CIDR to the app VM's private IP or subnet, e.g. 10.0.1.15/32}"
DB_PASSWORD="${DB_PASSWORD:?set DB_PASSWORD}"

apt-get update -y
apt-get install -y postgresql

PG_VERSION=$(psql -V | grep -oE '[0-9]+' | head -1)
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"

sudo -u postgres psql -c "CREATE ROLE cloudlab WITH LOGIN PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -c "CREATE DATABASE cloudlab OWNER cloudlab;"
sudo -u postgres psql -d cloudlab -v ON_ERROR_STOP=1 -f "$(dirname "$0")/../../db/schema.sql" \
  || echo "NOTE: copy db/schema.sql to this host and load it as the cloudlab role if this step failed."

# Listen on the private network interface, not just localhost.
sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" "${PG_CONF_DIR}/postgresql.conf"

# Only allow the app tier's CIDR in over the network; everything else stays
# local-only. Plain "host" (not "hostssl") to match the app's pg client,
# which doesn't request SSL — fine for a private lab subnet, not for
# anything crossing a public network.
echo "host cloudlab cloudlab ${APP_TIER_CIDR} scram-sha-256" >> "${PG_CONF_DIR}/pg_hba.conf"

systemctl restart postgresql

echo "Postgres ready. Also lock this down at the network layer:"
echo "  - security group / NSG: allow tcp/5432 from ${APP_TIER_CIDR} only, deny 0.0.0.0/0"
