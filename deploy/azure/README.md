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

Also note: `custom_data` embeds `db_password` and the Redis access key in
plaintext, visible via the Azure portal/CLI and in
`/var/log/cloud-init-output.log` on the VM. Fine for a throwaway lab; use
Key Vault + a managed identity for anything real.

## Tear down

```bash
terraform destroy
```
