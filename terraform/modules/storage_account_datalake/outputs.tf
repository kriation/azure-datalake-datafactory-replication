output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "filesystem_name" {
  value = var.filesystem_name
}

output "storage_account_id" {
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
