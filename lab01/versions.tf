terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  # azurerm 4.x requires the subscription ID explicitly
  # (or set the ARM_SUBSCRIPTION_ID environment variable instead).
  subscription_id = var.subscription_id
}
