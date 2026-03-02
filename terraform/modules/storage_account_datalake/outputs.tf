output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "filesystem_name" {
  value = azurerm_storage_data_lake_gen2_filesystem.this.name
}

output "storage_account_id" {
  value = azurerm_storage_account.this.id
}
