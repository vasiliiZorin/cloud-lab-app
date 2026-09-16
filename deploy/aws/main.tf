terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- Security groups: each tier only accepts what it needs -------------

resource "aws_security_group" "app" {
  name_prefix = "cloud-lab-app-"
  description = "App tier: HTTP from anywhere, SSH from admin IP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name_prefix = "cloud-lab-db-"
  description = "DB tier: Postgres from the app tier only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "cache" {
  name_prefix = "cloud-lab-cache-"
  description = "Cache tier: Redis from the app tier only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Managed data + cache tiers ------------------------------------------

resource "aws_db_subnet_group" "cloud_lab" {
  name       = "cloud-lab-db"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "db" {
  identifier             = "cloud-lab-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_encrypted      = true
  db_name                = "cloudlab"
  username               = "cloudlab"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.cloud_lab.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  apply_immediately      = true
}

resource "aws_elasticache_subnet_group" "cloud_lab" {
  name       = "cloud-lab-cache"
  subnet_ids = data.aws_subnets.default.ids
}

# A replication group (rather than a plain elasticache_cluster) is what
# lets ElastiCache require a password and encrypt traffic — a bare
# aws_elasticache_cluster has neither option.
resource "aws_elasticache_replication_group" "cache" {
  replication_group_id       = "cloud-lab-cache"
  description                = "cloud-lab-app cache tier"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = "cache.t3.micro"
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  parameter_group_name       = "default.redis7"
  subnet_group_name          = aws_elasticache_subnet_group.cloud_lab.name
  security_group_ids         = [aws_security_group.cache.id]
  transit_encryption_enabled = true
  auth_token                 = var.redis_password
  at_rest_encryption_enabled = true
}

# --- App tier: plain EC2 instance ----------------------------------------

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  root_block_device {
    encrypted = true
  }

  metadata_options {
    http_tokens = "required" # require IMDSv2, block the classic SSRF-to-credentials path
  }

  user_data = <<-EOF
    #cloud-config
    package_update: true
    write_files:
      - path: /opt/cloud-lab-app-env/.env
        content: |
          PORT=3000
          PGHOST=${aws_db_instance.db.address}
          PGPORT=5432
          PGUSER=cloudlab
          PGPASSWORD=${var.db_password}
          PGDATABASE=cloudlab
          PGSSLMODE=require
          REDIS_HOST=${aws_elasticache_replication_group.cache.primary_endpoint_address}
          REDIS_PORT=6379
          REDIS_PASSWORD=${var.redis_password}
          REDIS_TLS=true
    runcmd:
      - [ bash, -c, "apt-get install -y git postgresql-client && git clone ${var.app_git_repo} /opt/cloud-lab-app" ]
      - [ bash, -c, "cp /opt/cloud-lab-app-env/.env /opt/cloud-lab-app/.env" ]
      - [ bash, -c, "cd /opt/cloud-lab-app && PGSSLMODE=require psql \"postgresql://cloudlab:${var.db_password}@${aws_db_instance.db.address}:5432/cloudlab\" -f db/schema.sql || true" ]
      - [ bash, -c, "bash /opt/cloud-lab-app/deploy/common/install-app-vm.sh" ]
  EOF

  tags = {
    Name = "cloud-lab-app"
  }

  depends_on = [aws_db_instance.db, aws_elasticache_replication_group.cache]
}
