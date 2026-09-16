variable "image_name" {
  description = "OpenStack image to boot (check `openstack image list`), e.g. Ubuntu 22.04"
  type        = string
  default     = "Ubuntu 22.04"
}

variable "flavor_name" {
  description = "OpenStack flavor/size (check `openstack flavor list`)"
  type        = string
  default     = "m1.small"
}

variable "external_network_name" {
  description = "Name of the provider/external network to route floating IPs through"
  type        = string
  default     = "public"
}

variable "ssh_keypair_name" {
  description = "Name of an existing OpenStack keypair (create with `openstack keypair create`)"
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Your IP, as a /32 CIDR, allowed to SSH into the VMs"
  type        = string
}

variable "db_password" {
  description = "Password for the cloudlab Postgres role"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Password for Redis auth"
  type        = string
  sensitive   = true
}

variable "app_git_repo" {
  description = "Git URL the app VM clones on first boot (push this project there first)"
  type        = string
}
