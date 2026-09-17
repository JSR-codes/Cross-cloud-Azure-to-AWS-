variable "project_name" {
  type    = string
  default = "azure-to-aws-migration"
}

## ---------- Azure (source) ----------
variable "azure_subscription_id" {
  type = string
}

variable "azure_location" {
  type    = string
  default = "East US"
}

variable "azure_vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "azure_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "azure_vm_size" {
  description = "The 'on-prem-like' source VM size being migrated"
  type        = string
  default     = "Standard_B1s"
}

variable "azure_admin_username" {
  type    = string
  default = "azureuser"
}

variable "azure_ssh_public_key_path" {
  description = "Path to your SSH public key, used to log into the source VM"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

## ---------- AWS (migration target) ----------
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "aws_staging_subnet_cidr" {
  description = "Subnet MGN uses to land replicated data during migration"
  type        = string
  default     = "10.20.1.0/24"
}

variable "aws_target_subnet_cidr" {
  description = "Subnet the cutover instance launches into after migration"
  type        = string
  default     = "10.20.2.0/24"
}

variable "my_ip" {
  description = "Your IP in CIDR form, for SSH access to both the source and migrated instance"
  type        = string
}
