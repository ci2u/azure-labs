# ---------------------------------------------------------------
# Lab 02 - Storage account: blob container, data protection,
#          lifecycle management, firewall, RBAC, private endpoint
# AZ-104 topics: storage accounts, redundancy, access tiers,
#                versioning/soft delete, lifecycle rules, SAS,
#                storage firewall, private endpoints, RBAC data roles
# ---------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# Storage account names are global, 3-24 chars, lowercase letters/digits only
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ---------- Storage account ----------

resource "azurerm_storage_account" "st" {
  name                     = "st${var.prefix}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS" # cheapest; try GRS/ZRS in the exercises
  access_tier              = "Hot"
  tags                     = var.tags

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false # no anonymous blob access

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7 # soft delete for blobs
    }

    container_delete_retention_policy {
      days = 7 # soft delete for containers
    }
  }

  # Storage firewall: deny everything except your IP (and trusted Azure services).
  # IP rules don't accept /31 or /32, so the bare address is used.
  network_rules {
    default_action = "Deny"
    ip_rules       = [replace(var.my_ip, "/32", "")]
    bypass         = ["AzureServices"]
  }
}

# Created through the management plane (storage_account_id), so it works through the firewall
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.st.id
  container_access_type = "private"
}

# Lifecycle management: move blobs in "data" to cooler tiers, then delete them
resource "azurerm_storage_management_policy" "lifecycle" {
  storage_account_id = azurerm_storage_account.st.id

  rule {
    name    = "tier-and-expire-data"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["data/"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 365
      }

      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# ---------- RBAC ----------

# Lets you use the data plane with your Entra ID login (az ... --auth-mode login)
# instead of account keys. Owner on the subscription does NOT include data access.
resource "azurerm_role_assignment" "me_blob_contributor" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------- Private endpoint ----------

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefix}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

# The zone name is fixed by Azure for blob private endpoints
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-${var.prefix}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${azurerm_storage_account.st.name}-blob"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.st.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  # Registers the endpoint's private IP in the private DNS zone automatically
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
