terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # The bootstrap keeps LOCAL state on purpose: it creates the storage account
  # that every other stack stores its state in (chicken and egg - see exercise 7).
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
