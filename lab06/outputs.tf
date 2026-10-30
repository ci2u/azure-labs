output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "public_ip" {
  value = azurerm_public_ip.vm.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.vm.ip_address}"
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.law.name
}

output "workspace_id" {
  description = "Workspace (customer) ID used by KQL queries from the CLI"
  value       = azurerm_log_analytics_workspace.law.workspace_id
}
