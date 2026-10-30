variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab06"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "vm_size" {
  description = "Confidential VM size (2 vCPU, ECASv5 family)"
  type        = string
  default     = "Standard_EC2as_v5"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (curl.exe -s ifconfig.me). SSH is only allowed from here."
  type        = string
}

variable "alert_email" {
  description = "Email address the action group notifies"
  type        = string
}

variable "tags" {
  type = map(string)
  default = {
    environment = "lab"
    owner       = "az104-practice"
    managed_by  = "terraform"
  }
}
