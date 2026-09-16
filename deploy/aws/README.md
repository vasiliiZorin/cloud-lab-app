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
| RDS PostgreSQL (db) | db.t3.micro, 20GB | ~$0.02/hr + storage (free tier eligible for 12mo) |
| ElastiCache Redis (cache) | cache.t3.micro | ~$0.02/hr (not free-tier) |

None of this is free forever — **`terraform destroy` when you're done** or
you'll keep paying. RDS and ElastiCache are the ones people forget about.

## Steps

```bash
cd deploy/aws
cp terraform.tfvars.example terraform.tfvars
# edit: region, key_pair_name, admin_ssh_cidr, db_password, app_git_repo

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

Note: the ElastiCache cluster here has **no AUTH password** — plain
`aws_elasticache_cluster` doesn't support it (you'd need an
`aws_elasticache_replication_group` with transit encryption for that).
Network isolation (security group: only the app tier can reach it) is the
only thing standing between the internet and Redis, which is the AWS
default posture for a lab like this — don't reuse this for anything with
real data without adding a replication group + AUTH token.

Also note: `user_data` embeds `db_password` in plaintext (visible via the
EC2 console/API and in `/var/log/cloud-init-output.log` on the instance).
Fine for a throwaway lab; use Secrets Manager + an IAM instance role for
anything real.

## Tear down

```bash
terraform destroy
```
