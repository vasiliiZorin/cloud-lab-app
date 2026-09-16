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
Put them on the same private network.

Attach your **SSH public key** at creation time rather than a password —
Cyber Frame's own VM-access flow is key-based (generate/attach a keypair,
then connect over SSH), so there shouldn't be a password login option to
worry about in the first place.

If the private network isn't already routable to the internet, you'll
need a router connecting it to the public/external network before a
floating IP will work — this is the same OpenStack-style networking model
under Cyber Frame Cloud, so it may be a separate step from creating the
network itself.

Note each VM's **private IP** (and, for the app VM, its **public/floating
IP** — attach one if it isn't assigned automatically).

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

Use `sudo env VAR=value ...` (not `sudo VAR=value ...`) for every command
below — `sudo` doesn't reliably forward plain shell variable assignments
into the root environment unless you go through `env` explicitly, and a
silently-empty `DB_PASSWORD` is exactly the kind of thing you don't want
to discover after the fact.

## 4. Provision the db VM

```bash
ssh ubuntu@<db-vm-ip>
sudo git clone <your-repo-url> /opt/cloud-lab-app
cd /opt/cloud-lab-app
sudo env PRIVATE_IP=<db-vm-private-ip> APP_TIER_CIDR=<app-vm-private-ip>/32 \
  DB_PASSWORD='<pick-a-password>' bash deploy/common/install-db-vm.sh
```

## 5. Provision the cache VM

```bash
ssh ubuntu@<cache-vm-ip>
sudo git clone <your-repo-url> /opt/cloud-lab-app
cd /opt/cloud-lab-app
sudo env PRIVATE_IP=<cache-vm-private-ip> REDIS_PASSWORD='<pick-a-password>' \
  bash deploy/common/install-cache-vm.sh
```

## 6. Provision the app VM

```bash
ssh ubuntu@<app-vm-ip>
sudo git clone <your-repo-url> /opt/cloud-lab-app
cd /opt/cloud-lab-app
sudo cp .env.example .env
sudo nano .env   # set PGHOST=<db-vm-private-ip>, PGPASSWORD, REDIS_HOST=<cache-vm-private-ip>, REDIS_PASSWORD
sudo bash deploy/common/install-app-vm.sh   # dir already exists, so this just installs Node + the systemd unit
```

## 7. Verify

```bash
curl http://<app-vm-public-ip>:3000/healthz
# {"app":"ok","db":"ok","cache":"ok"}
```

Open `http://<app-vm-public-ip>:3000` in a browser and post a message.

## Security posture — and where it's weaker than the AWS/Azure deploys

This is the "pure IaaS" deployment, so you own the hardening the managed
services would otherwise do for you:

- **Network isolation** is real: the security-group table in step 2 means
  db/cache are unreachable from anywhere but the app VM, same as on
  AWS/Azure.
- **Postgres and Redis traffic is not encrypted** between the app VM and
  the db/cache VMs — `install-db-vm.sh`/`install-cache-vm.sh` set up
  password auth (`scram-sha-256` for Postgres, `requirepass` for Redis)
  but not TLS. On AWS/Azure this repo turns TLS on by default because
  those are managed services designed to be reached over less-trusted
  networks; here, self-managed Postgres/Redis on a private subnet you
  control is a more defensible place to skip it, but it's still a real
  difference — don't put this on a subnet you don't fully trust.
- **SSH**: key-based only (see step 1). Also worth doing once you're in:
  `sudo apt-get install -y unattended-upgrades && sudo dpkg-reconfigure
  --priority=low unattended-upgrades` on all three VMs, so they keep
  getting security patches without you remembering to `apt upgrade`.
- **Secrets**: passwords are typed directly into SSH commands/`.env`
  files rather than pulled from a secrets manager — Cyber Frame Cloud
  doesn't offer one via the portal today. `install-app-vm.sh` locks
  `.env` down to `chmod 600`, owned by the `www-data` user the app runs
  as, so at least other local users on the VM can't read it.

## Tear down

Delete the three VMs from the portal when you're done — Cyber Frame Cloud
bills for allocated compute/storage while they exist, same as any other
cloud.
