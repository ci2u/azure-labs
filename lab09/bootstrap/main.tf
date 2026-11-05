# ---------------------------------------------------------------
# Lab 09 bootstrap - run ONCE from your PC (local state)
# Creates everything the Terraform pipeline needs:
#
#   rg-lab09-tfstate
#     ├─ stlab09tfstateXXXX / container "tfstate"   ← remote state (versioning, soft delete)
#     ├─ id-lab09-plan   (OIDC: pull requests + main)  → Reader on rg-lab09
#     └─ id-lab09-apply  (OIDC: environment "production") → Contributor on rg-lab09
#   rg-lab09                                         ← the only place the pipeline can change
#
# Both identities (and you) get Storage Blob Data Contributor on the state container -
# reading state and taking the state lock (a blob lease) are data-plane operations.
# ---------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

# ---------- Remote state ----------

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.prefix}-tfstate"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "st${var.prefix}tfstate${random_string.suffix.result}" # globally unique
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Keys stay enabled so this bootstrap can manage the account easily.
  # The pipeline never uses them (use_azuread_auth) - exercise 6 turns them off.
  shared_access_key_enabled = true
  tags                      = var.tags

  blob_properties {
    versioning_enabled = true # every state write keeps the previous version

    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id # ARM API, no storage keys needed
  container_access_type = "private"
}

# ---------- The resource group the pipeline manages ----------

resource "azurerm_resource_group" "target" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ---------- Pipeline identities ----------

resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-${var.prefix}-plan"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "apply" {
  name                = "id-${var.prefix}-apply"
  location            = azurerm_resource_group.tfstate.location
  resource_group_name = azurerm_resource_group.tfstate.name
  tags                = var.tags
}

# Plan runs on pull requests and on main
resource "azurerm_federated_identity_credential" "plan_pr" {
  name      = "github-pull-request"
  parent_id = azurerm_user_assigned_identity.plan.id
  issuer    = "https://token.actions.githubusercontent.com"
  audience  = ["api://AzureADTokenExchange"]
  subject   = "repo:${var.github_repo}:pull_request"
}

resource "azurerm_federated_identity_credential" "plan_main" {
  name      = "github-main"
  parent_id = azurerm_user_assigned_identity.plan.id
  issuer    = "https://token.actions.githubusercontent.com"
  audience  = ["api://AzureADTokenExchange"]
  subject   = "repo:${var.github_repo}:ref:refs/heads/main"

  # Azure rejects two concurrent writes of federated credentials on one identity
  depends_on = [azurerm_federated_identity_credential.plan_pr]
}

# Apply only runs in a job that uses the protected environment
resource "azurerm_federated_identity_credential" "apply_env" {
  name      = "github-env-${var.github_environment}"
  parent_id = azurerm_user_assigned_identity.apply.id
  issuer    = "https://token.actions.githubusercontent.com"
  audience  = ["api://AzureADTokenExchange"]
  subject   = "repo:${var.github_repo}:environment:${var.github_environment}"
}

# ---------- Least-privilege role assignments ----------

resource "azurerm_role_assignment" "plan_reader" {
  scope                = azurerm_resource_group.target.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = azurerm_resource_group.target.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "plan_state" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_state" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
}

# You, for local `terraform init/plan` (Owner on the subscription doesn't include blob DATA access)
resource "azurerm_role_assignment" "me_state" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
