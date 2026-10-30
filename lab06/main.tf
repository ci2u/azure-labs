# ---------------------------------------------------------------
# Lab 06 - Azure Monitor
# AZ-104 topics: Log Analytics workspace, Azure Monitor Agent (AMA),
#                data collection rules, KQL, action groups,
#                metric / log search / activity log alerts,
#                diagnostic settings (activity log -> workspace)
#
#   vm-lab06 --AMA--> DCR (Perf + Syslog) --> law-lab06-xxxx
#      |                                          ^
#      | platform metric "Percentage CPU"         | subscription activity log
#      v                                          | (diagnostic setting)
#   metric alert (CPU > 80%)        log alert (failed SSH logins)
#   activity log alert (VM deallocated)
#            \___________ all three ___________/
#                           |
#                  action group -> email
# ---------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ---------- Log Analytics ----------

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5 # daily cap: ingestion stops for the day once reached
  tags                = var.tags
}

# Send the subscription's activity log to the workspace (AzureActivity table).
# Without this it's only kept for 90 days and you can't query it with KQL.
resource "azurerm_monitor_diagnostic_setting" "activity" {
  name                       = "diag-${var.prefix}-activity-to-law"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Policy"
  }
}

# ---------- Network ----------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefix}"
  address_space       = ["10.60.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.60.1.0/24"]
}

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-${var.prefix}-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SSH-MyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.my_ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_public_ip" "vm" {
  name                = "pip-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

# ---------- VM ----------

# Same confidential-VM setup as Lab 01 (EC2as_v5 needs it)
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "vm-${var.prefix}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.vm.id]
  tags                  = var.tags

  disable_password_authentication = true
  secure_boot_enabled             = true
  vtpm_enabled                    = true

  # The Azure Monitor Agent authenticates to Azure with this identity
  identity {
    type = "SystemAssigned"
  }

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

# ---------- Azure Monitor Agent + data collection rule ----------

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags
}

# The DCR says WHAT to collect and WHERE to send it; the agent alone collects nothing
resource "azurerm_monitor_data_collection_rule" "linux" {
  name                = "dcr-${var.prefix}-linux"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = "law"
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["law"]
  }

  data_sources {
    # Guest-level counters - memory and disk usage aren't platform metrics
    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "Processor(*)\\% Processor Time",
        "Memory(*)\\% Used Memory",
        "Logical Disk(*)\\% Used Space",
      ]
    }

    # auth/authpriv carry sshd's login messages
    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "syslog"]
      log_levels     = ["*"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "vm" {
  name                    = "dcra-${var.prefix}"
  target_resource_id      = azurerm_linux_virtual_machine.vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux.id
}

# ---------- Alerts ----------

resource "azurerm_monitor_action_group" "email" {
  name                = "ag-${var.prefix}-email"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "lab06" # max 12 chars, shown in SMS/email
  tags                = var.tags

  email_receiver {
    name                    = "me"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Metric alert on a platform metric - works even without the agent
resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "alert-${var.prefix}-cpu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine.vm.id]
  description         = "Average CPU above 80% for 5 minutes"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

# Log search alert - a KQL query over data the agent sent to the workspace
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "ssh_failures" {
  name                 = "alert-${var.prefix}-ssh-failures"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  scopes               = [azurerm_log_analytics_workspace.law.id]
  description          = "More than 5 failed SSH logins in 5 minutes"
  severity             = 2
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  tags                 = var.tags

  criteria {
    query                   = <<-KQL
      Syslog
      | where Facility in ("auth", "authpriv")
      | where SyslogMessage has_any ("Invalid user", "Failed password", "Connection closed by invalid user")
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 5
  }

  action {
    action_groups = [azurerm_monitor_action_group.email.id]
  }

  # The Syslog table doesn't exist until the agent sends its first record
  skip_query_validation = true
}

# Activity log alert - fires on a control-plane operation, not on data
resource "azurerm_monitor_activity_log_alert" "deallocate" {
  name                = "alert-${var.prefix}-vm-deallocated"
  location            = "global"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_resource_group.rg.id]
  description         = "A VM in this resource group was deallocated"
  tags                = var.tags

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/deallocate/action"
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}
