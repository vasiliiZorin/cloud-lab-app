# Deployment concepts, once, instead of three times

Each `deploy/<provider>/` folder has its own README with exact steps. This
page is the vocabulary that carries across all of them, so the per-provider
docs don't have to re-explain it.

## The same three security boundaries, three names

Every provider gives you a way to say "only let traffic from X reach this
thing." That's the mechanism keeping the db/cache tiers off the public
internet in every one of these deployments.

| Concept | Acronis Cyber Frame (OpenStack) | AWS | Azure |
|---|---|---|---|
| Firewall attached to a VM/service | Security Group | Security Group | Network Security Group (NSG) |
| Isolated network | Network + Subnet | VPC + Subnet | Virtual Network (VNet) + Subnet |
| Public IP | Floating IP | Elastic IP / public IP | Public IP |
| "Only the app tier can reach the db" | secgroup rule scoped to the subnet CIDR | secgroup rule scoped to another security group | NSG rule / firewall rule scoped to an IP |

## IaaS vs. managed service — the actual point of this lab

- **Acronis Cyber Frame Cloud** gives you compute, storage, networking —
  full stop. Postgres and Redis are just more VMs you patch, back up, and
  scale yourself. This is what "cloud" meant before managed data services
  existed, and it's still what you get from a lot of providers.
- **AWS** and **Azure** offer the same VM primitive, but *also* a managed
  Postgres (RDS / Flexible Server) and managed Redis (ElastiCache / Azure
  Cache) where the provider handles patching, backups, and failover. You
  pay more per-GB for that; you stop thinking about it.

Deploying literally the same app three ways is the fastest way to feel that
difference — on Acronis you'll `ssh` into a db VM and run `apt install
postgresql`; on AWS/Azure you'll never see the machine Postgres runs on.

## Health checks and load balancers

`/healthz` (in [server/index.js](../server/index.js)) checks that the app
can actually reach both the db and cache tiers, not just that the process
is alive. That's the pattern every cloud load balancer / auto-scaling
group health check expects — point one at `:3000/healthz` if you extend
any of these deploys to add a load balancer in front of multiple app
instances.

## Secrets, honestly

None of these Terraform configs use a secrets manager — passwords go into
`terraform.tfvars` (gitignored) and get written into each VM's
cloud-init `user_data`/`custom_data`, which is visible in plaintext via
each provider's console/API and in the instance's boot log. That's a
reasonable simplification for a personal lab you'll tear down; it is not
how you'd do this for anything with real users or data (that's what AWS
Secrets Manager, Azure Key Vault, and OpenStack Barbican are for).
