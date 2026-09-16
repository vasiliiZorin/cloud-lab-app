terraform {
  required_version = ">= 1.5"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
  }
}

# Auth comes from environment variables (source openrc.sh before running
# terraform) rather than being hardcoded here.
provider "openstack" {}

# --- Networking ---------------------------------------------------------

resource "openstack_networking_network_v2" "cloud_lab" {
  name           = "cloud-lab-net"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "cloud_lab" {
  name       = "cloud-lab-subnet"
  network_id = openstack_networking_network_v2.cloud_lab.id
  cidr       = "10.0.1.0/24"
  ip_version = 4
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

data "openstack_networking_network_v2" "external" {
  name = var.external_network_name
}

resource "openstack_networking_router_v2" "cloud_lab" {
  name                = "cloud-lab-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "cloud_lab" {
  router_id = openstack_networking_router_v2.cloud_lab.id
  subnet_id = openstack_networking_subnet_v2.cloud_lab.id
}

# --- Security groups: each tier only accepts what it needs -------------

resource "openstack_networking_secgroup_v2" "app" {
  name                 = "cloud-lab-app"
  description          = "App tier: HTTP from anywhere, SSH from admin IP"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "app_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3000
  port_range_max    = 3000
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "app_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_v2" "db" {
  name                 = "cloud-lab-db"
  description          = "DB tier: Postgres from the app tier only, SSH from admin IP"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "db_postgres" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = "${openstack_networking_subnet_v2.cloud_lab.cidr}"
  security_group_id = openstack_networking_secgroup_v2.db.id
}

resource "openstack_networking_secgroup_rule_v2" "db_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.db.id
}

resource "openstack_networking_secgroup_v2" "cache" {
  name                 = "cloud-lab-cache"
  description          = "Cache tier: Redis from the app tier only, SSH from admin IP"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "cache_redis" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6379
  port_range_max    = 6379
  remote_ip_prefix  = "${openstack_networking_subnet_v2.cloud_lab.cidr}"
  security_group_id = openstack_networking_secgroup_v2.cache.id
}

resource "openstack_networking_secgroup_rule_v2" "cache_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.admin_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.cache.id
}

# --- Instances -----------------------------------------------------------

resource "openstack_compute_instance_v2" "db" {
  name        = "cloud-lab-db"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = var.ssh_keypair_name
  security_groups = [openstack_networking_secgroup_v2.db.name]

  network {
    uuid = openstack_networking_network_v2.cloud_lab.id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    runcmd:
      - [ bash, -c, "apt-get install -y git && git clone ${var.app_git_repo} /opt/cloud-lab-app" ]
      - [ bash, -c, "cd /opt/cloud-lab-app && APP_TIER_CIDR='${openstack_networking_subnet_v2.cloud_lab.cidr}' DB_PASSWORD='${var.db_password}' bash deploy/common/install-db-vm.sh" ]
  EOF

  depends_on = [openstack_networking_router_interface_v2.cloud_lab]
}

resource "openstack_compute_instance_v2" "cache" {
  name        = "cloud-lab-cache"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = var.ssh_keypair_name
  security_groups = [openstack_networking_secgroup_v2.cache.name]

  network {
    uuid = openstack_networking_network_v2.cloud_lab.id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    runcmd:
      - [ bash, -c, "apt-get install -y git && git clone ${var.app_git_repo} /opt/cloud-lab-app" ]
      - [ bash, -c, "cd /opt/cloud-lab-app && PRIVATE_IP=$(hostname -I | awk '{print $1}') REDIS_PASSWORD='${var.redis_password}' bash deploy/common/install-cache-vm.sh" ]
  EOF

  depends_on = [openstack_networking_router_interface_v2.cloud_lab]
}

resource "openstack_compute_instance_v2" "app" {
  name        = "cloud-lab-app"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = var.ssh_keypair_name
  security_groups = [openstack_networking_secgroup_v2.app.name]

  network {
    uuid = openstack_networking_network_v2.cloud_lab.id
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    write_files:
      - path: /opt/cloud-lab-app-env/.env
        content: |
          PORT=3000
          PGHOST=${openstack_compute_instance_v2.db.access_ip_v4}
          PGPORT=5432
          PGUSER=cloudlab
          PGPASSWORD=${var.db_password}
          PGDATABASE=cloudlab
          REDIS_HOST=${openstack_compute_instance_v2.cache.access_ip_v4}
          REDIS_PORT=6379
          REDIS_PASSWORD=${var.redis_password}
    runcmd:
      - [ bash, -c, "apt-get install -y git && git clone ${var.app_git_repo} /opt/cloud-lab-app" ]
      - [ bash, -c, "cp /opt/cloud-lab-app-env/.env /opt/cloud-lab-app/.env" ]
      - [ bash, -c, "bash /opt/cloud-lab-app/deploy/common/install-app-vm.sh" ]
  EOF

  depends_on = [
    openstack_networking_router_interface_v2.cloud_lab,
    openstack_compute_instance_v2.db,
    openstack_compute_instance_v2.cache,
  ]
}

resource "openstack_networking_floatingip_v2" "app" {
  pool = var.external_network_name
}

resource "openstack_compute_floatingip_associate_v2" "app" {
  floating_ip = openstack_networking_floatingip_v2.app.address
  instance_id = openstack_compute_instance_v2.app.id
}
