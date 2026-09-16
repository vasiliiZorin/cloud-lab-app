variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH access"
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Your IP, as a /32 CIDR, allowed to SSH into the app instance"
  type        = string
}

variable "db_password" {
  description = "Password for the cloudlab Postgres role (RDS master password)"
  type        = string
  sensitive   = true
}

variable "app_git_repo" {
  description = "Git URL the app instance clones on first boot"
  type        = string
}
