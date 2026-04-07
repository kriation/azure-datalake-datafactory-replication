resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  min_tls_version                 = var.min_tls_version
  public_network_access_enabled   = var.public_network_access_enabled
  is_hns_enabled                  = false
  large_file_share_enabled        = true

  dynamic "blob_properties" {
    for_each = var.soft_delete_days > 0 || var.versioning_enabled || var.change_feed_enabled ? [1] : []
    content {
      versioning_enabled  = var.versioning_enabled
      change_feed_enabled = var.change_feed_enabled

      dynamic "delete_retention_policy" {
        for_each = var.soft_delete_days > 0 ? [1] : []
        content {
          days = var.soft_delete_days
        }
      }

      dynamic "container_delete_retention_policy" {
        for_each = var.soft_delete_days > 0 ? [1] : []
        content {
          days = var.soft_delete_days
        }
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      customer_managed_key,
    ]
  }
}

resource "azurerm_storage_share" "fileshare" {
  name               = "fileshare"
  storage_account_id = azurerm_storage_account.this.id
  quota              = 100
  enabled_protocol   = "SMB"
}

output "name" {
  value = azurerm_storage_account.this.name
}

output "fileshare_url" {
  value = azurerm_storage_share.fileshare.url
}

output "primary_connection_string" {
  value = azurerm_storage_account.this.primary_connection_string
}

output "id" {
  value = azurerm_storage_account.this.id
}

output "principal_id" {
  value = azurerm_storage_account.this.identity[0].principal_id
}

output "min_tls_version" {
  value = azurerm_storage_account.this.min_tls_version
}

output "public_network_access_enabled" {
  value = azurerm_storage_account.this.public_network_access_enabled
}
