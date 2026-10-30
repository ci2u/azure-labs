output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "lb_public_ip" {
  value = azurerm_public_ip.lb.ip_address
}

output "url" {
  value = "http://${azurerm_public_ip.lb.ip_address}"
}

output "ssh_commands" {
  description = "SSH to each VM through its inbound NAT rule"
  value = {
    for k, vm in local.vms :
    k => "ssh -p ${vm.ssh_port} ${var.admin_username}@${azurerm_public_ip.lb.ip_address}"
  }
}
