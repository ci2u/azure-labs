variable "subscription_id" {
  description = "Your Azure subscription ID (az account show --query id -o tsv)"
  type        = string
}

variable "prefix" {
  description = "Short prefix used in all resource names"
  type        = string
  default     = "lab08"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "northeurope"
}

variable "github_repo" {
  description = "GitHub repository (owner/name) whose workflows are allowed to log in to Azure"
  type        = string
  default     = "ci2u/azure-labs"
}

variable "github_branch" {
  description = "Only workflow runs on this branch get a token Azure accepts"
  type        = string
  default     = "main"
}

variable "github_environment" {
  description = "Exercise 7: GitHub environment that is also trusted (jobs using an environment get a different token subject)"
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
