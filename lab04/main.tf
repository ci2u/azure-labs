# ---------------------------------------------------------------
# Lab 04 - Hub and spoke networking
# AZ-104 topics: VNet peering (and why it isn't transitive), NSGs,
#                application security groups, user-defined routes,
#                effective routes/rules, Network Watcher diagnostics
#
#   vnet-hub  10.40.0.0/16  (snet-shared 10.40.1.0/24 - "NVA" lives at .4)
#      |  peering        |  peering
#   vnet-spoke1          vnet-spoke2
#   10.41.0.0/16         10.42.0.0/16
#   vm-spoke1 10.41.1.4  vm-spoke2 10.42.1.4
#   (public IP, ASG jump) (private only, ASG app)
# ---------------------------------------------------------------

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ---------- VNets and subnets ----------

locals {
  vnets = {
    hub    = { cidr = "10.40.0.0/16", subnet_name = "snet-shared", subnet_cidr = "10.40.1.0/24" }
    spoke1 = { cidr = "10.41.0.0/16", subnet_name = "snet-workload", subnet_cidr = "10.41.1.0/24" }
    spoke2 = { cidr = "10.42.0.0/16", subnet_name = "snet-workload", subnet_cidr = "10.42.1.0/24" }
  }

  # Hub <-> each spoke. Peering is one-directional, so every pair needs two resources.
  peerings = {
    hub-to-spoke1 = { from = "hub", to = "spoke1" }
    spoke1-to-hub = { from = "spoke1", to = "hub" }
    hub-to-spoke2 = { from = "hub", to = "spoke2" }
    spoke2-to-hub = { from = "spoke2", to = "hub" }
  }

  nva_ip = "10.40.1.4" # nothing is deployed here - used by the UDR exercise
}

resource "azurerm_virtual_network" "vnet" {
  for_each = local.vnets

  name                = "vnet-${each.key}"
  address_space       = [each.value.cidr]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "subnet" {
  for_each = local.vnets

  name                 = each.value.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[each.key].name
  address_prefixes     = [each.value.subnet_cidr]
}

resource "azurerm_virtual_network_peering" "peer" {
  for_each = local.peerings

  name                      = each.key
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet[each.value.from].name
  remote_virtual_network_id = azurerm_virtual_network.vnet[each.value.to].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true  # accept traffic an NVA in the hub forwards
  allow_gateway_transit        = false # no VPN/ExpressRoute gateway in this lab
  use_remote_gateways          = false
}

# ---------- Application security groups ----------

# ASGs group NICs by role, so NSG rules say "to app servers" instead of listing IPs
resource "azurerm_application_security_group" "jump" {
  name                = "asg-jump"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_application_security_group" "app" {
  name                = "asg-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# ---------- NSGs ----------

resource "azurerm_network_security_group" "spoke1" {
  name                = "nsg-spoke1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                                       = "Allow-SSH-MyIP-to-Jump"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "22"
    source_address_prefix                      = var.my_ip
    destination_application_security_group_ids = [azurerm_application_security_group.jump.id]
  }
}

resource "azurerm_network_security_group" "spoke2" {
  name                = "nsg-spoke2"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  # Ping from anywhere in the (peered) network is fine...
  security_rule {
    name                                       = "Allow-ICMP-VNet-to-App"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Icmp"
    source_port_range                          = "*"
    destination_port_range                     = "*"
    source_address_prefix                      = "VirtualNetwork"
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }

  # ...but nothing else. Without this, the default AllowVnetInBound (65000) would allow SSH too.
  security_rule {
    name                                       = "Deny-VNet-to-App"
    priority                                   = 4000
    direction                                  = "Inbound"
    access                                     = "Deny"
    protocol                                   = "*"
    source_port_range                          = "*"
    destination_port_range                     = "*"
    source_address_prefix                      = "VirtualNetwork"
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }
}

resource "azurerm_subnet_network_security_group_association" "spoke1" {
  subnet_id                 = azurerm_subnet.subnet["spoke1"].id
  network_security_group_id = azurerm_network_security_group.spoke1.id
}

resource "azurerm_subnet_network_security_group_association" "spoke2" {
  subnet_id                 = azurerm_subnet.subnet["spoke2"].id
  network_security_group_id = azurerm_network_security_group.spoke2.id
}

# ---------- User-defined route (exercise 5, off by default) ----------

resource "azurerm_route_table" "spoke1" {
  count = var.enable_udr ? 1 : 0

  name                = "rt-spoke1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  route {
    name                   = "spoke2-via-hub-nva"
    address_prefix         = local.vnets.spoke2.cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.nva_ip
  }
}

resource "azurerm_subnet_route_table_association" "spoke1" {
  count = var.enable_udr ? 1 : 0

  subnet_id      = azurerm_subnet.subnet["spoke1"].id
  route_table_id = azurerm_route_table.spoke1[0].id
}

# ---------- VMs ----------

locals {
  vms = {
    spoke1 = { private_ip = "10.41.1.4", asg_id = azurerm_application_security_group.jump.id, public = true }
    spoke2 = { private_ip = "10.42.1.4", asg_id = azurerm_application_security_group.app.id, public = false }
  }
}

resource "azurerm_public_ip" "jump" {
  name                = "pip-${var.prefix}-spoke1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "vm" {
  for_each = local.vms

  name                = "nic-${var.prefix}-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = each.value.public ? azurerm_public_ip.jump.id : null
  }
}

resource "azurerm_network_interface_application_security_group_association" "vm" {
  for_each = local.vms

  network_interface_id          = azurerm_network_interface.vm[each.key].id
  application_security_group_id = each.value.asg_id
}

# Same confidential-VM setup as Lab 01 (EC2as_v5 needs it)
resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.vms

  name                  = "vm-${var.prefix}-${each.key}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm[each.key].id]
  tags                  = var.tags

  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching                  = "ReadWrite"
    storage_account_type     = "Standard_LRS"
    security_encryption_type = "VMGuestStateOnly"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "cvm"
    version   = "latest"
  }
}
