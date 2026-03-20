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
