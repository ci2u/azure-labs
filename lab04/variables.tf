variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab04"
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
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (curl.exe -s ifconfig.me). SSH to the jump VM is only allowed from here."
  type        = string
}

variable "enable_udr" {
  description = "Exercise 5: attach a route table to spoke1 that sends spoke2 traffic to a (non-existent) NVA in the hub"
  type        = bool
  default     = false
}

variable "tags" {
  type = map(string)
  default = {
    environment = "lab"
    owner       = "az104-practice"
    managed_by  = "terraform"
  }
}
