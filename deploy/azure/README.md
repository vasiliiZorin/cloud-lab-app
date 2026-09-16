# Deploying to Azure

Same split as [AWS](../aws/): app tier is a VM you manage, db/cache are
managed services (Azure Database for PostgreSQL Flexible Server, Azure
Cache for Redis) reached over their public endpoint through an IP
allow-list — Azure's Basic/Standard Redis tier isn't VNet-injected the way
Premium is, so "restrict to the app VM's IP" is the realistic posture here,
not a VNet.

Azure Database for PostgreSQL **requires TLS by default**; the app already
handles that (`PGSSLMODE=require` is set in this VM's `.env`, which makes
`server/db.js` request TLS — see [db.js](../../server/db.js)).

## Security posture

- **Postgres**: not just relying on TLS — `azurerm_postgresql_flexible_server_firewall_rule`
  allow-lists only the app VM's public IP, so nothing else can even attempt
  a connection. TLS on top of that protects the traffic on the wire.
- **Redis**: `non_ssl_port_enabled = false`, so the plaintext port 6379
  is off entirely — the app connects on the SSL port with `REDIS_TLS=true`
  (see [cache.js](../../server/cache.js)), authenticated with Azure's
  `primary_access_key`, on top of the same IP allow-list as Postgres.
- **VM**: `disable_password_authentication = true` — SSH key only, no
  password login possible even if someone got the admin username right.
  Only ports 22 (from your IP) and 3000 (public) are open via the NSG.

What's still a lab-grade shortcut: `custom_data` embeds `db_password` and
the Redis access key in plaintext, visible via the Azure portal/CLI and
in `/var/log/cloud-init-output.log` on the VM. Fine for a throwaway lab;
use Key Vault + a managed identity for anything real. The app also
doesn't validate the Postgres/Redis TLS certificate
(`rejectUnauthorized: false`) — you still get encryption in transit, just
not certificate-pinned protection against a man-in-the-middle between the
VM and Azure's managed services.

## Prerequisites

- An Azure account, logged in locally: `az login`.
- Terraform >= 1.5.
- An SSH keypair (`ssh-keygen -t ed25519 -f ~/.ssh/cloud_lab_azure` if you
  don't have one you want to reuse).
- This app pushed to a git repo the VM can clone at boot.

## What this creates (and what it costs)

| Resource | Size | Approx. cost while running |
|---|---|---|
| Linux VM (app) | Standard_B1s | ~$0.01/hr |
| Azure Database for PostgreSQL Flexible Server (db) | B_Standard_B1ms, 32GB | ~$0.02/hr + storage |
| Azure Cache for Redis (cache) | Basic C0 | ~$0.02/hr |

**`terraform destroy` when you're done** — the Postgres and Redis services
bill continuously while they exist, not per-request.

## Steps

```bash
cd deploy/azure
az login
cp terraform.tfvars.example terraform.tfvars
# edit: location, admin_ssh_cidr, ssh_public_key_path, db_password, app_git_repo

terraform init
terraform plan     # review before applying
terraform apply
```

```bash
terraform output app_public_ip
curl http://$(terraform output -raw app_public_ip):3000/healthz
```

Resource names for the Postgres server and Redis cache must be globally
unique across Azure, so this config suffixes them with a random hex string
(`random_id` provider) — check `terraform plan` output if you want to see
the actual generated names before creating anything.

## Tear down

```bash
terraform destroy
```
