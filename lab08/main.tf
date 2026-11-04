# ---------------------------------------------------------------
# Lab 08 - CI/CD with GitHub Actions
# Topics: pipeline stages (test -> build -> deploy), OIDC workload
#         identity federation (no secrets in GitHub), least-privilege
#         pipeline identity, ACR, Azure Container Apps revisions
#
#   git push ──► GitHub Actions (.github/workflows/lab08-ci-cd.yml)
#                  test ─► build+push ─► deploy ─► smoke test
#                             │  OIDC token: "repo:<owner>/<repo>:ref:refs/heads/main"
#                             ▼
#                  id-lab08-github (federated credential trusts that subject)
#                    ├─ AcrPush     on acrlab08xxxx
#                    └─ Contributor on rg-lab08 (to update the container app)
#
#   ca-lab08 (Container Apps, scales to zero) ──pulls with id-lab08-pull (AcrPull)──► ACR
# ---------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ---------- Container registry ----------

resource "azurerm_container_registry" "acr" {
  name                = "acr${var.prefix}${random_string.suffix.result}" # globally unique, letters and digits only
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
}

# ---------- Identity the pipeline logs in as ----------

resource "azurerm_user_assigned_identity" "github" {
  name                = "id-${var.prefix}-github"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# GitHub signs a short-lived token for each job; Azure swaps it for an access
# token only if issuer, audience and subject match exactly. No secret involved.
resource "azurerm_federated_identity_credential" "github_branch" {
  name      = "github-${var.github_branch}"
  parent_id = azurerm_user_assigned_identity.github.id
  issuer    = "https://token.actions.githubusercontent.com"
  audience  = ["api://AzureADTokenExchange"]
  subject   = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
}

# A job that uses `environment: production` gets this subject instead (exercise 7)
resource "azurerm_federated_identity_credential" "github_environment" {
  name      = "github-env-${var.github_environment}"
  parent_id = azurerm_user_assigned_identity.github.id
  issuer    = "https://token.actions.githubusercontent.com"
  audience  = ["api://AzureADTokenExchange"]
  subject   = "repo:${var.github_repo}:environment:${var.github_environment}"

  # Azure doesn't allow writing two federated credentials on one identity at the same time
  depends_on = [azurerm_federated_identity_credential.github_branch]
}

resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# Scoped to this resource group only - the pipeline can't touch anything else
resource "azurerm_role_assignment" "github_rg_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------- Identity the container app pulls images with ----------

resource "azurerm_user_assigned_identity" "pull" {
  name                = "id-${var.prefix}-pull"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "pull_acr" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.pull.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------- Container Apps ----------

resource "azurerm_container_app_environment" "env" {
  name                = "cae-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  # Azure now creates every environment with this built-in serverless profile.
  # Declaring it stops a perpetual "remove workload_profile" diff on every plan.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app" "app" {
  name                         = "ca-${var.prefix}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # run on the serverless profile (scale to zero)
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.pull.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.pull.id
  }

  ingress {
    external_enabled = true
    target_port      = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0 # scale to zero when idle - you pay nothing then
    max_replicas = 2

    container {
      name = "hello"
      # Placeholder until the pipeline's first run - a public sample that also listens on 8080
      image  = "mcr.microsoft.com/dotnet/samples:aspnetapp"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "GREETING"
        value = "Hello"
      }
    }
  }

  # The pipeline owns the image from now on; without this, every terraform apply
  # would roll the app back to the placeholder
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.pull_acr]
}
