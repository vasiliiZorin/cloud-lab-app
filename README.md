# Cloud Lab Guestbook

A deliberately small 3-tier app for learning how different cloud providers
handle the same workload shapes. No containers — just a process, a database,
and a cache, the way you'd have run things a decade ago, so the *cloud
provider's* job (compute, managed DB, managed cache, networking, load
balancing) is the only new variable.

## Architecture

```
 ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
 │   app server  │──────│   database   │      │    cache     │
 │  Node/Express │──────┼──────────────┼──────│    Redis     │
 │  (port 3000)  │      │  PostgreSQL  │      │ visit counter│
 └──────┬───────┘      └──────────────┘      └──────────────┘
        │
   serves static HTML/JS (public/) + a tiny JSON API
```

- **App server** — stateless Node/Express process. Serves the frontend and a
  JSON API (`/api/messages`, `/api/visit`, `/healthz`). This is the workload
  every cloud calls "compute."
- **Database** — PostgreSQL. Durable storage for guestbook messages. This is
  the workload every cloud offers either as "just a VM you manage" (IaaS) or
  as a managed service (RDS, Azure Database for PostgreSQL, ...).
- **Cache** — Redis. Holds a visit counter — fast, ephemeral, disposable.
  Same IaaS-vs-managed-service split as the database.

`/healthz` reports whether the app can actually reach both the db and cache
tiers — that's the endpoint a cloud load balancer's health check would poll.

## Run it locally

Prerequisites: Node.js, a Postgres server, a Redis server (installed via
Homebrew is fine: `brew install postgresql@16 redis`).

```bash
# 1. create the app's database/role and load the schema
psql -d postgres -c "CREATE ROLE cloudlab WITH LOGIN PASSWORD 'localdevpassword';"
psql -d postgres -c "CREATE DATABASE cloudlab OWNER cloudlab;"
psql -U cloudlab -d cloudlab -f db/schema.sql   # run AS cloudlab so it owns the table

# 2. configure the app
cp .env.example .env   # edit PGPASSWORD to match above

# 3. install deps and run
npm install
npm start              # -> http://localhost:3000
```

If your Homebrew Postgres refuses to start with `postmaster became
multithreaded during startup`, start it with `LC_ALL=C LANG=C pg_ctl ... start`
— a known locale/threading quirk on recent macOS.

## Deploying to the cloud

Same app, three different providers, three different ways of running the db
and cache tiers — that contrast is the point:

| Provider | App server | Database | Cache | Notes |
|---|---|---|---|---|
| [Acronis Cyber Frame Cloud](deploy/acronis/README.md) | VM | VM (self-hosted Postgres) | VM (self-hosted Redis) | Pure IaaS, provisioned manually (portal + SSH) — no usable API/Terraform path yet |
| [AWS](deploy/aws/README.md) | EC2 | RDS (managed Postgres) | ElastiCache (managed Redis) | Compute vs. managed-service split is explicit; provisioned with Terraform |
| [Azure](deploy/azure/README.md) | VM | Azure Database for PostgreSQL (Flexible Server) | Azure Cache for Redis | Same split, Azure's naming; provisioned with Terraform |

Each `deploy/<provider>/` folder has a README with the required steps,
credentials, and — importantly — **what it will cost and how to tear it
down**. AWS and Azure use Terraform (`terraform apply` after reviewing the
plan); Acronis is manual portal + SSH steps, since Terraform isn't an
option there yet. Nothing in this repo provisions anything by itself.

Start with whichever provider you have an account on. `deploy/README.md`
has the shared concepts (security groups vs NSGs vs Cyber Frame's firewall
rules, etc.) so you're not re-learning them three times.
