variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab09"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "github_repo" {
  description = <<-EOT
    Repository part of the GitHub OIDC subject. Repos created after 15 July 2026 use
    immutable IDs: "owner@<owner id>/repo@<repo id>" (copy it from an AADSTS700213 error
    or from the Lab 08 tfvars).
  EOT
  type        = string
  default     = "ci2u@333288156/azure-labs@1438202702"
}

variable "github_environment" {
  description = "GitHub environment whose jobs may run terraform apply"
  type        = string
  default     = "production"
}

variable "tags" {
  type = map(string)
  default = {
    environment = "lab"
    owner       = "az104-practice"
    managed_by  = "terraform"
  }
}
