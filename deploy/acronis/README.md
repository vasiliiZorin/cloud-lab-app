# Deploying to Acronis Cyber Frame Cloud (manual)

Cyber Frame Cloud doesn't expose a usable API/Terraform path yet, so this
is a manual, portal + SSH deployment — no IaC here, unlike the
[AWS](../aws/) and [Azure](../azure/) folders. That's fine: it's still the
same three-tier shape, and it's arguably more honest about what "IaaS"
meant before every provider had a Terraform provider.

The [`deploy/common/`](../common) scripts do the actual provisioning work
(install Postgres/Redis/Node, write the systemd unit, open the right
ports) — you're just running them over SSH instead of via `user_data`.

## 1. Create three VMs in the Cyber Frame Cloud portal

App, db, cache — one VM each, Ubuntu 22.04 or 24.04, smallest size that's
available (this app is tiny; 1 vCPU / 1-2GB RAM is plenty for all three).
Put them on the same private network if the portal lets you choose one.

Note each VM's **private IP** (and, for the app VM, its **public/floating
IP** if the portal assigns one automatically, or attach one manually if
it's a separate step).

## 2. Lock down access with the portal's security groups / firewall rules

Whatever Cyber Frame Cloud calls this screen, you're creating the same
three rule sets as any cloud (see [deploy/README.md](../README.md) for the
cross-provider vocabulary):

| VM | Allow inbound | From |
|---|---|---|
| app | TCP 22 | your IP only |
| app | TCP 3000 | anywhere (0.0.0.0/0) — this is the public entry point |
| db | TCP 22 | your IP only |
| db | TCP 5432 | the app VM's private IP only |
| cache | TCP 22 | your IP only |
| cache | TCP 6379 | the app VM's private IP only |

Everything else inbound: deny. If the portal defaults to "allow all" for
a new VM, tighten it before moving on — that's the whole point of having
three separate VMs instead of one.

## 3. Push the app to a git repo

The install scripts `git clone` it. Push what's in this directory
(`cloud-lab-app/`) to GitHub/GitLab/wherever — a public repo is simplest
for a lab like this.

## 4. Provision the db VM

```bash
ssh ubuntu@<db-vm-ip>
sudo git clone <your-repo-url> /opt/cloud-lab-app
cd /opt/cloud-lab-app
sudo APP_TIER_CIDR=<app-vm-private-ip>/32 DB_PASSWORD='<pick-a-password>' \
  bash deploy/common/install-db-vm.sh
```

## 5. Provision the cache VM

```bash
ssh ubuntu@<cache-vm-ip>
sudo git clone <your-repo-url> /opt/cloud-lab-app
cd /opt/cloud-lab-app
sudo PRIVATE_IP=<cache-vm-private-ip> REDIS_PASSWORD='<pick-a-password>' \
  bash deploy/common/install-cache-vm.sh
```

## 6. Provision the app VM

```bash
ssh ubuntu@<app-vm-ip>
sudo git clone <your-repo-url> /opt/cloud-lab-app
cd /opt/cloud-lab-app
sudo cp .env.example .env
sudo nano .env   # set PGHOST=<db-vm-private-ip>, PGPASSWORD, REDIS_HOST=<cache-vm-private-ip>, REDIS_PASSWORD
sudo GIT_REPO="" bash deploy/common/install-app-vm.sh   # dir already exists, so this just installs Node + the systemd unit
```

## 7. Verify

```bash
curl http://<app-vm-public-ip>:3000/healthz
# {"app":"ok","db":"ok","cache":"ok"}
```

Open `http://<app-vm-public-ip>:3000` in a browser and post a message.

## Tear down

Delete the three VMs from the portal when you're done — Cyber Frame Cloud
bills for allocated compute/storage while they exist, same as any other
cloud.
