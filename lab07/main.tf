# ---------------------------------------------------------------
# Lab 07 - Azure Container Registry + Azure Kubernetes Service
# Topics: Docker images, private registry, AKS cluster,
#         managed identities (kubelet -> AcrPull),
#         Deployments, Services, rolling updates, probes, ConfigMaps
#
#   your PC: docker build ──push──► acrlab07xxxx (ACR, Basic)
#                                        │ AcrPull (kubelet identity)
#                                        ▼
#   kubectl ──(only from my_ip)──► aks-lab07 (Free tier, 1 node)
#                                        │ Service type LoadBalancer
#                                        ▼
#                         MC_rg-lab07_... : Azure LB + public IP
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

# ---------- Container registry ----------

resource "azurerm_container_registry" "acr" {
  name                = "acr${var.prefix}${random_string.suffix.result}" # globally unique, letters and digits only
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false # use Entra ID identities, not a shared admin password
  tags                = var.tags
}

# ---------- AKS ----------

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aks-${var.prefix}-${random_string.suffix.result}"
  sku_tier            = "Free" # no control-plane charge, no uptime SLA
  tags                = var.tags

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    os_sku                      = "Ubuntu"
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "tmpsystem"

    upgrade_settings {
      max_surge = "1"
    }
  }

  # The cluster's own identity manages Azure resources (LB rules, public IPs)
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # pods get IPs from a private overlay range, not from the VNet
    load_balancer_sku   = "standard"
  }

  # The API server is public, but only your IP may talk to it
  api_server_access_profile {
    authorized_ip_ranges = [var.my_ip]
  }
}

# Nodes pull images with the kubelet identity - give it pull rights on the registry
# (the same thing `az aks update --attach-acr` does)
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
