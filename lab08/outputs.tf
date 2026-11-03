output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "container_app_name" {
  value = azurerm_container_app.app.name
}

output "app_url" {
  value = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}

# Copy these into GitHub: repo Settings -> Secrets and variables -> Actions -> Variables.
# None of them is a secret - with OIDC there's no password to store.
output "github_variables" {
  value = {
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.github.client_id
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    ACR_NAME              = azurerm_container_registry.acr.name
    RESOURCE_GROUP        = azurerm_resource_group.rg.name
    CONTAINER_APP         = azurerm_container_app.app.name
  }
}
