# Deploying to AWS

Contrast with the [Acronis](../acronis/) deployment: here the db and cache
tiers are **managed services** (RDS, ElastiCache), not VMs you patch. Only
the app tier is a VM (EC2) you manage yourself.

## Prerequisites

- An AWS account, `aws configure`'d locally (access key + secret, or SSO).
- Terraform >= 1.5.
- An existing EC2 key pair in the target region (`aws ec2 create-key-pair
  --key-name cloud-lab --query 'KeyMaterial' --output text > cloud-lab.pem
  && chmod 400 cloud-lab.pem`), or reuse one you already have.
- This app pushed to a git repo the EC2 instance can clone at boot
  (public repo, or a private one with a deploy token baked into the URL —
  keep it out of source control either way).

This uses your **default VPC** to keep the Terraform short. If you don't
have one (some older accounts don't, or you deleted it), create it first:
`aws ec2 create-default-vpc`.

## What this creates (and what it costs)

| Resource | Size | Approx. cost while running |
|---|---|---|
| EC2 instance (app) | t3.micro | ~$0.01/hr (free tier eligible) |
| RDS PostgreSQL (db), encrypted at rest | db.t3.micro, 20GB | ~$0.02/hr + storage (free tier eligible for 12mo) |
| ElastiCache Redis (cache), AUTH + TLS | cache.t3.micro replication group | ~$0.02/hr (not free-tier) |

None of this is free forever — **`terraform destroy` when you're done** or
you'll keep paying. RDS and ElastiCache are the ones people forget about.

## Steps

```bash
cd deploy/aws
cp terraform.tfvars.example terraform.tfvars
# edit: region, key_pair_name, admin_ssh_cidr, db_password, redis_password, app_git_repo

terraform init
terraform plan     # review what will be created and confirm the region/cost
terraform apply
```

```bash
terraform output app_public_ip
curl http://$(terraform output -raw app_public_ip):3000/healthz
```

The `.env` on the app instance is written by `user_data` at boot, pointing
`PGHOST` at the RDS endpoint and `REDIS_HOST` at the ElastiCache endpoint —
both created and torn down by this same Terraform, so there's no manual
wiring step like there is on Acronis.

## Security posture

- **RDS**: not publicly accessible (`publicly_accessible = false`), only
  reachable from the app tier's security group, encrypted at rest
  (`storage_encrypted = true`), and the app connects with
  `PGSSLMODE=require` (encrypted in transit).
- **ElastiCache**: this uses `aws_elasticache_replication_group`, not the
  simpler `aws_elasticache_cluster` — the plain cluster resource has no
  AUTH/encryption option at all. The replication group requires an
  `auth_token` (password) and `transit_encryption_enabled = true`, so
  Redis is both authenticated and TLS-encrypted, on top of the same
  network isolation (security group: only the app tier can reach it).
- **EC2**: only ports 22 (from your IP) and 3000 (public, since it's the
  app's front door) are open; the root volume is encrypted
  (`root_block_device.encrypted = true`); IMDSv2 is required
  (`metadata_options.http_tokens = "required"`), which closes off the
  classic SSRF-to-instance-credentials path some Metadata Service v1
  vulnerabilities relied on.

What's still a lab-grade shortcut, not a production posture: `user_data`
embeds `db_password` and `redis_password` in plaintext (visible via the
EC2 console/API and in `/var/log/cloud-init-output.log` on the instance).
Fine for a throwaway lab; use Secrets Manager + an IAM instance role for
anything real. The app also doesn't validate the RDS/ElastiCache TLS
certificate (`rejectUnauthorized: false` in [server/db.js](../../server/db.js) /
[server/cache.js](../../server/cache.js)) — it still gets you encryption
in transit, just not certificate-pinned protection against a
man-in-the-middle inside your own VPC, which is a narrow threat model to
begin with.

## Tear down

```bash
terraform destroy
```
