variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names (lowercase letters/digits only - it goes into the storage account name)"
  type        = string
  default     = "lab02"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (curl.exe -s ifconfig.me). Only this IP gets through the storage firewall."
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
