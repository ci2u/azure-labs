variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab05"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "vm_size" {
  description = "Confidential VM size. Two of these = 4 vCPU = your whole ECASv5 quota in northeurope."
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
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (curl.exe -s ifconfig.me). HTTP and SSH are only allowed from here."
  type        = string
}

variable "load_distribution" {
  description = "Exercise 3: Default (5-tuple hash), SourceIP (2-tuple) or SourceIPProtocol (3-tuple)"
  type        = string
  default     = "Default"

  validation {
    condition     = contains(["Default", "SourceIP", "SourceIPProtocol"], var.load_distribution)
    error_message = "load_distribution must be Default, SourceIP or SourceIPProtocol."
  }
}

variable "tags" {
  type = map(string)
  default = {
    environment = "lab"
    owner       = "az104-practice"
    managed_by  = "terraform"
  }
}
