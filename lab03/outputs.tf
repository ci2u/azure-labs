output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "operator_identity_name" {
  value = azurerm_user_assigned_identity.operator.name
}

output "operator_principal_id" {
  value = azurerm_user_assigned_identity.operator.principal_id
}

output "custom_role_name" {
  value = azurerm_role_definition.vm_operator.name
}

output "custom_policy_name" {
  value = azurerm_policy_definition.deny_public_ip.name
}
