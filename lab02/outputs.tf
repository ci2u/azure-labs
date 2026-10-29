output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = azurerm_storage_account.st.name
}

output "blob_endpoint" {
  value = azurerm_storage_account.st.primary_blob_endpoint
}

output "container_name" {
  value = azurerm_storage_container.data.name
}

output "private_endpoint_ip" {
  value = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
}
