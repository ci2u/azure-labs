variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab07"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "node_vm_size" {
  description = "AKS node size. EC2as_v5 (2 vCPU, 16 GB) is the size your quota allows; AKS runs it as a confidential VM node."
  type        = string
  default     = "Standard_EC2as_v5"
}

variable "node_count" {
  description = "Number of nodes. 1 node = 2 of your 4 cores; an upgrade surges one more."
  type        = number
  default     = 1
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32 (curl.exe -s ifconfig.me). Only this IP can reach the Kubernetes API (kubectl)."
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
