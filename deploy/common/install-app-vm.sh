#!/usr/bin/env bash
# Provisions a bare Ubuntu 22.04/24.04 VM to run the app-server tier:
# installs Node.js, pulls the app, installs a systemd unit.
# Run as root (e.g. as cloud-init user_data, or manually over SSH).
#
# Expects the app source to already be present at /opt/cloud-lab-app
# (rsync/scp it there, or set GIT_REPO below to git-clone it).
set -euo pipefail

GIT_REPO="${GIT_REPO:-}"   # optional: git clone this instead of rsync'ing manually
APP_DIR=/opt/cloud-lab-app

if [[ -n "$GIT_REPO" && ! -d "$APP_DIR" ]]; then
  apt-get update -y
  apt-get install -y git
  git clone "$GIT_REPO" "$APP_DIR"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: $APP_DIR not found and GIT_REPO not set. Copy the app there first." >&2
  exit 1
fi

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

cd "$APP_DIR"
npm install --omit=dev

if [[ ! -f "$APP_DIR/.env" ]]; then
  echo "WARNING: $APP_DIR/.env not present — copy .env.example and fill in" \
       "PGHOST/REDIS_HOST etc. before starting the service." >&2
fi

install -m 644 deploy/common/cloud-lab-app.service /etc/systemd/system/cloud-lab-app.service
systemctl daemon-reload
systemctl enable cloud-lab-app
systemctl restart cloud-lab-app || echo "Service install done — start it once .env is in place."
