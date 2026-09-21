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

## Point-to-site VPN (WireGuard on the firewall)

Once OPNsense is the only way in and out, it's also the natural place to
terminate a VPN: it already sees every packet, so nothing has to be
re-routed to reach it. No extra VM is involved. WireGuard on OPNsense
26.1 is a kernel module (`if_wg.ko`), not a daemon — it adds one virtual
interface (`wg0`) to the firewall you already have, and no measurable
load.

What it buys over the SSH jump host: the app on `10.0.1.241:3000` and
the OPNsense GUI on `https://10.0.1.250` become reachable from your
laptop by private address, with no new port forwards and nothing newly
exposed except UDP 51820 — which is silent to scanners, since WireGuard
never replies to an unauthenticated packet.

### Addressing

The tunnel gets its own subnet — `10.10.0.0/24` here, firewall `.1`,
client `.2/32` — deliberately **not** part of `10.0.1.0/24`. A client
holding a `10.0.1.x` address would be ARPed for on the LAN segment by
any VM replying to it, and it isn't on that wire, so the replies would
be dropped and connections would hang. Pick any range that doesn't
collide with the lab, the transit network, the DR site, or whatever
commercial VPN you use day to day.

**WireGuard assigns nothing.** The client address is written by hand in
two places that must agree: `tunneladdress` on the peer (the firewall's
permission) and `Address` in the client config (the client's claim). If
they disagree the handshake still succeeds and every packet is then
silently dropped — a confusing failure, because `wg show` looks healthy.

### Firewall rules — the part that will waste your time

Two rules are needed:

1. **WAN**: allow `udp/51820` to the firewall. Straightforward.
2. **Tunnel**: allow `10.10.0.0/24 -> 10.0.1.0/24`. **This must be a
   floating rule.** `wg0` is not an assigned OPNsense interface, so a
   rule bound to interface `wg` produces `#debug:Interface wg not found`
   and is silently commented out of the generated ruleset — while the
   GUI continues to display it as active. A floating rule emits
   `pass in quick inet from ... to ...` with no interface clause, which
   matches on `wg0` regardless of assignment.

Verify with `pfctl -sr | grep 10.10.0`. If it isn't there it isn't
loaded, whatever the GUI shows. `grep "debug:" /tmp/rules.debug` reveals
what the generator rejected. This is the same class of silent failure as
picking a named service instead of a literal port number.

Rule ordering is fine even though OPNsense's `block drop in log inet
all` appears earlier in the list: that rule is not `quick`, so a later
`quick` pass rule still wins.

### Persistence

`plugins.inc.d/wireguard.inc` registers `'vpn' => ['wireguard_configure_do']`
and `rc.bootup` calls `plugins_configure('vpn', true)`, gated only on
`general/enabled == '1'`. The interface is therefore rebuilt at boot
even if you created it by hand while setting up.

### Client

Generate a keypair locally; the private half never leaves your machine:

```
wg genkey | tee client.key | wg pubkey > client.pub
```

Register the **public** key on the firewall as a peer with
`tunneladdress 10.10.0.2/32`. The client config is eight lines:

```
[Interface]
PrivateKey = <contents of client.key>
Address    = 10.10.0.2/32

[Peer]
PublicKey  = <the firewall's public key>
Endpoint   = <floating IP>:51820
AllowedIPs = 10.0.1.0/24, 10.10.0.0/24
PersistentKeepalive = 25
```

`AllowedIPs` here is a split tunnel — only lab traffic uses the VPN and
normal internet stays direct. Keep it narrow. For contrast, Acronis's DR
OpenVPN pushes `route 10.0.0.0/8`, which claims the entire ten-space and
collides with any commercial VPN using `10.x`; that collision is an
unpleasant afternoon to diagnose, because the tunnel connects fine and
only the routing is wrong.

On macOS: `brew install wireguard-tools`, put the config in
`/opt/homebrew/etc/wireguard/`, then `sudo wg-quick up cloud-lab`.

Note there is no TCP fallback — WireGuard is UDP-only by design. On a
network that blocks UDP or non-standard ports, this tunnel simply will
not connect, and SSH on port 22 remains the way in.

### Security groups still apply

The VPN puts you on the network; it does **not** bypass Cyber Frame
security groups. Over the tunnel your source address is `10.10.0.2`, so
only rules admitting it will let you through. The app's `:3000` rule
(`0.0.0.0/0`) works, and the OPNsense GUI works because the firewall VM
has no security group attached — but `:22` on the app, `5432` on the db
and `6379` on the cache stay blocked until you add `10.10.0.0/24` as an
allowed source in the portal.

Whether you should is a judgement call rather than an oversight:
reaching Postgres directly from a laptop is convenient, and keeping it
reachable only from the app tier is the more defensible posture.

## Tear down

Delete the three VMs from the portal when you're done — Cyber Frame Cloud
bills for allocated compute/storage while they exist, same as any other
cloud.
