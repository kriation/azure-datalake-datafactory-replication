output "name" {
  value = azurerm_storage_account.this.name
}

output "id" {
  value = azurerm_storage_account.this.id
}

output "principal_id" {
  value = azurerm_storage_account.this.identity[0].principal_id
}

output "container_name" {
  value = azurerm_storage_container.checkpoints.name
}
