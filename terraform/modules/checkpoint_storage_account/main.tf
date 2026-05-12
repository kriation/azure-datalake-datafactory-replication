resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  is_hns_enabled                  = false

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = var.soft_delete_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_days
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_storage_container" "checkpoints" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "checkpoint_retention" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "checkpoint-version-retention"
    enabled = true

    filters {
      prefix_match = [
        "${var.container_name}/${var.journal_prefix}/",
        "${var.container_name}/${var.current_prefix}/"
      ]
      blob_types = ["blockBlob"]
    }

    actions {
      version {
        delete_after_days_since_creation = var.version_retention_days
      }

      snapshot {
        delete_after_days_since_creation_greater_than = var.version_retention_days
      }
    }
  }
}

resource "azurerm_storage_container_immutability_policy" "checkpoint_container" {
  # Keep demo-regulated mode writable for checkpoint head updates.
  # Strict mode enables container-level immutability.
  count = var.journal_immutability_days > 0 && var.immutability_mode == "strict-regulated" ? 1 : 0

  storage_container_resource_manager_id = azurerm_storage_container.checkpoints.id
  immutability_period_in_days           = var.journal_immutability_days
  locked                                = true
  protected_append_writes_all_enabled   = true
}
