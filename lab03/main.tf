# ---------------------------------------------------------------
# Lab 03 - Governance: RBAC and Azure Policy
# AZ-104 topics: built-in vs custom roles, role assignments and scope,
#                managed identities, policy definitions/assignments,
#                Deny vs Modify effects, compliance, remediation
# Everything is scoped to the lab resource group, so the rest of the
# subscription is not affected. All of it is free.
# ---------------------------------------------------------------

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# Custom role and policy definition names must be unique in the tenant/subscription
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# ===============================================================
# RBAC
# ===============================================================

# A "service principal" to hand roles to - no Entra ID admin rights needed
resource "azurerm_user_assigned_identity" "operator" {
  name                = "id-${var.prefix}-operator"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# Custom role: can see VMs and start/stop/restart them, nothing else
resource "azurerm_role_definition" "vm_operator" {
  name        = "Lab03 VM Operator (${random_string.suffix.result})"
  scope       = azurerm_resource_group.rg.id
  description = "Read, start, restart and deallocate VMs. Cannot create, change or delete them."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.rg.id]
}

# Built-in role at resource-group scope
resource "azurerm_role_assignment" "operator_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.operator.principal_id
}

# Custom role at resource-group scope
resource "azurerm_role_assignment" "operator_vm" {
  scope              = azurerm_resource_group.rg.id
  role_definition_id = azurerm_role_definition.vm_operator.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.operator.principal_id
}

# ===============================================================
# Azure Policy
# ===============================================================

# --- Built-in definitions (looked up by their fixed GUID names) ---

data "azurerm_policy_definition" "allowed_locations" {
  name = "e56962a6-4747-49cd-b67b-bf8b01975c4c" # Allowed locations
}

data "azurerm_policy_definition" "require_tag" {
  name = "871b6d14-10aa-478d-b590-94f262ecfa99" # Require a tag on resources
}

data "azurerm_policy_definition" "inherit_tag" {
  name = "ea3f2387-9b95-492a-a190-fcdc54f7b070" # Inherit a tag from the resource group if missing
}

# --- Custom definition ---

resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "${var.prefix}-deny-public-ip-${random_string.suffix.result}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Lab03 - Deny public IP addresses"
  description  = "Blocks creation of public IP addresses."

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Network/publicIPAddresses"
    }
    then = {
      effect = "deny"
    }
  })
}

# --- Assignments (all at resource-group scope) ---

resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Only ${var.location}"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = { value = [var.location] }
  })
}

resource "azurerm_resource_group_policy_assignment" "require_tag" {
  name                 = "require-${var.required_tag}"
  display_name         = "Require tag '${var.required_tag}'"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.require_tag.id

  parameters = jsonencode({
    tagName = { value = var.required_tag }
  })
}

resource "azurerm_resource_group_policy_assignment" "deny_public_ip" {
  name                 = "deny-public-ip"
  display_name         = "Deny public IPs"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = azurerm_policy_definition.deny_public_ip.id
}

# Modify effect: the assignment needs its own managed identity + a role,
# because the policy itself changes resources (adds the tag).
resource "azurerm_resource_group_policy_assignment" "inherit_env_tag" {
  name                 = "inherit-environment-tag"
  display_name         = "Inherit 'environment' tag from RG"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.inherit_tag.id
  location             = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    tagName = { value = "environment" }
  })
}

resource "azurerm_role_assignment" "inherit_env_tag" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor" # the role the built-in policy definition asks for
  principal_id         = azurerm_resource_group_policy_assignment.inherit_env_tag.identity[0].principal_id
}
