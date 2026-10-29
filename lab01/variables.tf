variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab01"
}

variable "location" {
  description = "Azure region. If the VM size is unavailable here, try westeurope, northeurope or swedencentral."
  type        = string
  default     = "northeurope"
}

variable "vm_size" {
  description = "Confidential VM size (AMD SEV-SNP), 2 vCPU / 8 GiB. Must be a DC*as/DC*ads size - main.tf configures the VM as confidential."
  type        = string
  default     = "Standard_DC2as_v6"
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
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (curl ifconfig.me). SSH is only allowed from here."
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
