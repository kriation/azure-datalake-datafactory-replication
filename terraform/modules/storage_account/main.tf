resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version           = "TLS1_2"
  is_hns_enabled            = false
  large_file_share_enabled  = true
}

resource "azurerm_storage_share" "fileshare" {
  name                 = "fileshare"
  storage_account_name = azurerm_storage_account.this.name
  quota                = 100
  enabled_protocol     = "SMB"
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
