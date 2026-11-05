terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Remote state. resource_group_name and storage_account_name come from
  # `terraform init -backend-config=...` (the pipeline reads them from GitHub variables).
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "lab09.tfstate"
    use_azuread_auth = true # Entra ID + RBAC on the blob, never storage account keys
  }
}

# No credentials in code:
# - in the pipeline: ARM_USE_OIDC, ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID env vars
# - on your PC: your `az login` session (set $env:ARM_SUBSCRIPTION_ID first)
provider "azurerm" {
  features {}

  # The pipeline identities only have rights on rg-lab09, not on the subscription,
  # so they can't register resource providers - don't let Terraform try.
  resource_provider_registrations = "none"
}
