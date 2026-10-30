output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "jump_public_ip" {
  value = azurerm_public_ip.jump.ip_address
}

output "ssh_command" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.jump.ip_address}"
}

output "private_ips" {
  value = { for k, nic in azurerm_network_interface.vm : k => nic.private_ip_address }
}
