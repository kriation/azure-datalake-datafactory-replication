terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}
resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  account_kind                    = "StorageV2"
  allow_nested_items_to_be_public = false
  min_tls_version                 = var.min_tls_version
  public_network_access_enabled   = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      customer_managed_key,
    ]
  }
}

resource "time_sleep" "filesystem_propagation_wait" {
  create_duration = var.filesystem_create_wait

  depends_on = [
    azurerm_storage_account.this,
  ]
}

resource "azurerm_storage_data_lake_gen2_filesystem" "this" {
  count              = var.create_filesystem ? 1 : 0
  name               = var.filesystem_name
  storage_account_id = azurerm_storage_account.this.id

  depends_on = [
    time_sleep.filesystem_propagation_wait,
  ]
}
