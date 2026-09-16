# Deploying to Acronis Cyber Frame Cloud

Cyber Frame Cloud is **pure IaaS**: VMs, networks, floating IPs, security
groups. There is no managed Postgres or Redis service to reach for, so all
three tiers here are VMs you provision and patch yourself — that's the
whole point of including this provider in the lab.

Cyber Frame is built on OpenStack (via Virtuozzo) and exposes an
**OpenStack-compatible API**, so it's provisioned with the standard
[`terraform-provider-openstack/openstack`](https://registry.terraform.io/providers/terraform-provider-openstack/openstack)
provider rather than a bespoke one. Terraform-wise this deploys the same way
you'd deploy to any OpenStack private cloud.

## Prerequisites

1. An Acronis Cyber Frame Cloud tenant/project. If you already have
   Acronis-related credentials in your environment (the account referenced
   by your local `acronis-reregister.sh` is for Acronis Cyber Protect agent
   registration — a different product/token; you'll need separate Cyber
   Frame Cloud IaaS project credentials).
2. From the Cyber Frame Cloud portal: an `openrc.sh`-style credentials file
   (OpenStack auth URL, project/tenant, username/password or application
   credential, region). Acronis's IaaS onboarding docs show where to
   download this per-project.
3. Terraform >= 1.5, and the OpenStack CLI (`pip install python-openstackclient`)
   is handy for poking around before committing to Terraform.

```bash
source openrc.sh   # sets OS_AUTH_URL, OS_PROJECT_NAME, OS_USERNAME, OS_PASSWORD, OS_REGION_NAME...
openstack image list      # sanity check: can we reach the API?
openstack network list
```

## What this Terraform creates

- A private network + subnet (`cloud-lab-net`)
- A router with an external gateway (so VMs can reach the internet for
  `apt-get`/npm during provisioning)
- Three security groups (app / db / cache), each opening only the ports
  the *other* tiers need, plus SSH from your IP
- Three VM instances (app, db, cache), each running the matching
  `deploy/common/install-*.sh` script via `user_data` on first boot
- One floating IP, attached to the app VM only (db/cache stay private)

## Steps

```bash
cd deploy/acronis
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: image name, flavor name, your SSH key name,
# your IP for the SSH security-group rule, and the db/redis passwords

terraform init
terraform plan     # READ THIS before applying — confirms what will be created/billed
terraform apply
```

After apply, Terraform prints the app VM's floating IP. The app itself
still needs its `.env` pointed at the db/cache VMs' private IPs (also
printed as outputs) — the `user_data` scripts write a starter `.env`, but
double-check it matches `deploy/../.env.example`.

```bash
terraform output app_public_ip
curl http://<app_public_ip>:3000/healthz
```

## Tear down

```bash
terraform destroy
```

Acronis bills IaaS by allocated compute/storage/floating-IP while running —
destroy the stack when you're done experimenting, same as you would on any
other cloud.
