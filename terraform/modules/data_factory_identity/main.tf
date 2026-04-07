terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

resource "azurerm_data_factory" "this" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  managed_virtual_network_enabled = true

  identity {
    type = "SystemAssigned"
  }
}
