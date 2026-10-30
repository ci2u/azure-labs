# ---------------------------------------------------------------
# Lab 05 - Public Standard Load Balancer
# AZ-104 topics: frontend IP, backend pool, health probe,
#                load-balancing rule (distribution mode),
#                inbound NAT rules, outbound rules (SNAT),
#                NSGs with a Standard LB (secure by default)
#
#                 Internet (only your IP)
#                        |
#           pip-lab05-lb  (frontend "fe-public")
#                        |
#                    lb-lab05
#      rule  :80    -> backend pool :80   (probe GET / every 5 s)
#      NAT   :50001 -> vm1:22,  NAT :50002 -> vm2:22
#      outbound rule: VMs go out to the Internet as the frontend IP
#                 /                 \
#        vm-lab05-1 10.50.1.4   vm-lab05-2 10.50.1.5
#        nginx, no public IP    nginx, no public IP
# ---------------------------------------------------------------

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ---------- Network ----------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefix}"
  address_space       = ["10.50.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.1.0/24"]
}

# A Standard LB is closed by default: nothing reaches the VMs unless an NSG allows it.
# Rules see the packet AFTER the LB translated it, so the ports here are the
# backend ports (80, 22) - not the frontend NAT ports 50001/50002.
# Health probes come from 168.63.129.16 and are allowed by the default
# AllowAzureLoadBalancerInBound rule (65001).
resource "azurerm_network_security_group" "web" {
  name                = "nsg-${var.prefix}-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-HTTP-MyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# ---------- Load balancer ----------

resource "azurerm_public_ip" "lb" {
  name                = "pip-${var.prefix}-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard" # a Standard LB needs a Standard public IP
  tags                = var.tags
}

resource "azurerm_lb" "lb" {
  name                = "lb-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "fe-public"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  name            = "be-web"
  loadbalancer_id = azurerm_lb.lb.id
}

# A VM only gets traffic while this returns HTTP 200
resource "azurerm_lb_probe" "http" {
  name                = "probe-http"
  loadbalancer_id     = azurerm_lb.lb.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 5
}

resource "azurerm_lb_rule" "http" {
  name                           = "rule-http"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fe-public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.http.id
  load_distribution              = var.load_distribution

  # Outbound connectivity comes from the explicit outbound rule below instead
  disable_outbound_snat = true
}

# One frontend port per VM, both translated to port 22 on the VM
resource "azurerm_lb_nat_rule" "ssh" {
  for_each = local.vms

  name                           = "nat-ssh-${each.key}"
  resource_group_name            = azurerm_resource_group.rg.name
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = each.value.ssh_port
  backend_port                   = 22
  frontend_ip_configuration_name = "fe-public"
}

# VMs without public IPs reach the Internet through the LB frontend (SNAT)
resource "azurerm_lb_outbound_rule" "out" {
  name                     = "outbound-all"
  loadbalancer_id          = azurerm_lb.lb.id
  protocol                 = "All"
  backend_address_pool_id  = azurerm_lb_backend_address_pool.web.id
  allocated_outbound_ports = 1024

  frontend_ip_configuration {
    name = "fe-public"
  }
}

# ---------- VMs ----------

locals {
  vms = {
    vm1 = { private_ip = "10.50.1.4", ssh_port = 50001 }
    vm2 = { private_ip = "10.50.1.5", ssh_port = 50002 }
  }

  # nginx serving a page that says which VM answered
  cloud_init = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - nginx
    runcmd:
      - echo "Hello from $(hostname)" > /var/www/html/index.html
  EOT
}

resource "azurerm_network_interface" "vm" {
  for_each = local.vms

  name                = "nic-${var.prefix}-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "vm" {
  for_each = local.vms

  network_interface_id    = azurerm_network_interface.vm[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id
}

resource "azurerm_network_interface_nat_rule_association" "vm" {
  for_each = local.vms

  network_interface_id  = azurerm_network_interface.vm[each.key].id
  ip_configuration_name = "ipconfig1"
  nat_rule_id           = azurerm_lb_nat_rule.ssh[each.key].id
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
  custom_data           = base64encode(local.cloud_init)
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

  # cloud-init installs nginx on first boot, so outbound access must exist first
  depends_on = [
    azurerm_lb_outbound_rule.out,
    azurerm_network_interface_backend_address_pool_association.vm,
    azurerm_subnet_network_security_group_association.web,
  ]
}
