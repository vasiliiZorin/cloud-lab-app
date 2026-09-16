#!/usr/bin/env bash
# Provisions a bare Ubuntu 22.04/24.04 VM to run the database tier:
# installs PostgreSQL, creates the app role/database, loads the schema,
# and opens it to connections from the app-tier's private IP only.
#
# Usage: PRIVATE_IP=10.0.1.10 APP_TIER_CIDR=10.0.1.15/32 DB_PASSWORD=... ./install-db-vm.sh
set -euo pipefail

PRIVATE_IP="${PRIVATE_IP:?set PRIVATE_IP to this VMs own private IP}"
APP_TIER_CIDR="${APP_TIER_CIDR:?set APP_TIER_CIDR to the app VMs private IP or subnet, e.g. 10.0.1.15/32}"
DB_PASSWORD="${DB_PASSWORD:?set DB_PASSWORD}"

apt-get update -y
apt-get install -y postgresql

PG_VERSION=$(psql -V | grep -oE '[0-9]+' | head -1)
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"

# Pass the password as a psql variable rather than interpolating it into
# the SQL text, so quotes/backslashes in DB_PASSWORD can't break the
# statement (or, worse, get interpreted as SQL).
sudo -u postgres psql -v pw="$DB_PASSWORD" -c "CREATE ROLE cloudlab WITH LOGIN PASSWORD :'pw';"
sudo -u postgres psql -c "CREATE DATABASE cloudlab OWNER cloudlab;"
sudo -u postgres psql -d cloudlab -v ON_ERROR_STOP=1 -f "$(dirname "$0")/../../db/schema.sql" \
  || echo "NOTE: copy db/schema.sql to this host and load it as the cloudlab role if this step failed."

# Listen only on loopback + this VM's private IP — not every interface,
# in case the VM ever picks up a public one.
sed -i "s/^#listen_addresses.*/listen_addresses = 'localhost,${PRIVATE_IP}'/" "${PG_CONF_DIR}/postgresql.conf"

# Only allow the app tier's CIDR in over the network; everything else stays
# local-only. Plain "host" (not "hostssl") to match the app's pg client,
# which doesn't request SSL — fine for a private lab subnet, not for
# anything crossing a public network.
echo "host cloudlab cloudlab ${APP_TIER_CIDR} scram-sha-256" >> "${PG_CONF_DIR}/pg_hba.conf"

systemctl restart postgresql

echo "Postgres ready. Also lock this down at the network layer:"
echo "  - security group / NSG: allow tcp/5432 from ${APP_TIER_CIDR} only, deny 0.0.0.0/0"
