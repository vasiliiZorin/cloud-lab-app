variable "location" {
  type    = string
  default = "eastus"
}

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_ssh_cidr" {
  description = "Your IP, as a /32 CIDR, allowed to SSH into the app VM"
  type        = string
}

variable "db_password" {
  description = "Password for the cloudlab Postgres role"
  type        = string
  sensitive   = true
}

variable "app_git_repo" {
  description = "Git URL the app VM clones on first boot"
  type        = string
}
