terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "azurerm_resource_group" "cloud_lab" {
  name     = "cloud-lab-rg"
  location = var.location
}

# --- Networking ------------------------------------------------------------

resource "azurerm_virtual_network" "cloud_lab" {
  name                = "cloud-lab-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.cloud_lab.location
  resource_group_name = azurerm_resource_group.cloud_lab.name
}

resource "azurerm_subnet" "cloud_lab" {
  name                 = "cloud-lab-subnet"
  resource_group_name  = azurerm_resource_group.cloud_lab.name
  virtual_network_name = azurerm_virtual_network.cloud_lab.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_public_ip" "app" {
  name                = "cloud-lab-app-ip"
  location            = azurerm_resource_group.cloud_lab.location
  resource_group_name = azurerm_resource_group.cloud_lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "app" {
  name                = "cloud-lab-app-nsg"
  location            = azurerm_resource_group.cloud_lab.location
  resource_group_name = azurerm_resource_group.cloud_lab.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ssh_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "app" {
  name                = "cloud-lab-app-nic"
  location            = azurerm_resource_group.cloud_lab.location
  resource_group_name = azurerm_resource_group.cloud_lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.cloud_lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }
}

resource "azurerm_network_interface_security_group_association" "app" {
  network_interface_id     = azurerm_network_interface.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# --- Managed data + cache tiers ---------------------------------------------

resource "azurerm_postgresql_flexible_server" "db" {
  name                          = "cloud-lab-db-${random_id.suffix.hex}"
  resource_group_name           = azurerm_resource_group.cloud_lab.name
  location                      = azurerm_resource_group.cloud_lab.location
  version                       = "16"
  administrator_login           = "cloudlab"
  administrator_password        = var.db_password
  storage_mb                    = 32768
  sku_name                      = "B_Standard_B1ms"
  public_network_access_enabled = true
  zone                          = "1"
}

resource "azurerm_postgresql_flexible_server_database" "cloudlab" {
  name      = "cloudlab"
  server_id = azurerm_postgresql_flexible_server.db.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "app" {
  name             = "allow-app"
  server_id        = azurerm_postgresql_flexible_server.db.id
  start_ip_address = azurerm_public_ip.app.ip_address
  end_ip_address   = azurerm_public_ip.app.ip_address
}

resource "azurerm_redis_cache" "cache" {
  name                  = "cloud-lab-cache-${random_id.suffix.hex}"
  location              = azurerm_resource_group.cloud_lab.location
  resource_group_name   = azurerm_resource_group.cloud_lab.name
  capacity              = 0
  family                = "C"
  sku_name              = "Basic"
  non_ssl_port_enabled  = true
  minimum_tls_version   = "1.2"
}

resource "azurerm_redis_firewall_rule" "app" {
  name                = "allowapp"
  redis_cache_name    = azurerm_redis_cache.cache.name
  resource_group_name = azurerm_resource_group.cloud_lab.name
  start_ip            = azurerm_public_ip.app.ip_address
  end_ip              = azurerm_public_ip.app.ip_address
}

# --- App tier: plain Linux VM ------------------------------------------

resource "azurerm_linux_virtual_machine" "app" {
  name                            = "cloud-lab-app"
  resource_group_name             = azurerm_resource_group.cloud_lab.name
  location                        = azurerm_resource_group.cloud_lab.location
  size                            = var.vm_size
  admin_username                  = "azureuser"
  network_interface_ids           = [azurerm_network_interface.app.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #cloud-config
    package_update: true
    write_files:
      - path: /opt/cloud-lab-app-env/.env
        content: |
          PORT=3000
          PGHOST=${azurerm_postgresql_flexible_server.db.fqdn}
          PGPORT=5432
          PGUSER=cloudlab
          PGPASSWORD=${var.db_password}
          PGDATABASE=cloudlab
          PGSSLMODE=require
          REDIS_HOST=${azurerm_redis_cache.cache.hostname}
          REDIS_PORT=6379
          REDIS_PASSWORD=${azurerm_redis_cache.cache.primary_access_key}
    runcmd:
      - [ bash, -c, "apt-get install -y git postgresql-client && git clone ${var.app_git_repo} /opt/cloud-lab-app" ]
      - [ bash, -c, "cp /opt/cloud-lab-app-env/.env /opt/cloud-lab-app/.env" ]
      - [ bash, -c, "PGSSLMODE=require psql \"postgresql://cloudlab:${var.db_password}@${azurerm_postgresql_flexible_server.db.fqdn}:5432/cloudlab\" -f /opt/cloud-lab-app/db/schema.sql || true" ]
      - [ bash, -c, "bash /opt/cloud-lab-app/deploy/common/install-app-vm.sh" ]
  EOF
  )

  depends_on = [
    azurerm_network_interface_security_group_association.app,
    azurerm_postgresql_flexible_server_firewall_rule.app,
    azurerm_redis_firewall_rule.app,
  ]
}
