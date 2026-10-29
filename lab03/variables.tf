variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab03"
}

variable "location" {
  description = "Azure region - also the only region the 'Allowed locations' policy permits"
  type        = string
  default     = "northeurope"
}

variable "required_tag" {
  description = "Tag every resource in the lab RG must carry (enforced with a Deny policy)"
  type        = string
  default     = "costcenter"
}

variable "tags" {
  description = "Tags on the resource group. 'environment' is copied to resources by the inherit-tag policy."
  type        = map(string)
  default = {
    environment = "lab"
    owner       = "az104-practice"
    managed_by  = "terraform"
    costcenter  = "cc-1234"
  }
}
