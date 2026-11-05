# Repository variables for GitHub (Settings -> Secrets and variables -> Actions -> Variables).
# AZURE_TENANT_ID and AZURE_SUBSCRIPTION_ID already exist from Lab 08.
output "github_variables" {
  value = {
    LAB09_PLAN_CLIENT_ID  = azurerm_user_assigned_identity.plan.client_id
    LAB09_APPLY_CLIENT_ID = azurerm_user_assigned_identity.apply.client_id
    LAB09_TFSTATE_RG      = azurerm_resource_group.tfstate.name
    LAB09_TFSTATE_ACCOUNT = azurerm_storage_account.tfstate.name
  }
}

# For running `terraform init` in ../stack from your PC
output "backend_init_command" {
  value = "terraform init -backend-config=\"resource_group_name=${azurerm_resource_group.tfstate.name}\" -backend-config=\"storage_account_name=${azurerm_storage_account.tfstate.name}\""
}
