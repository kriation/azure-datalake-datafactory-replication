output "key_ids" {
  value = {
    for key_name, key_resource in azurerm_key_vault_key.this : key_name => key_resource.id
  }
}

output "versionless_key_ids" {
  value = {
    for key_name, key_resource in azurerm_key_vault_key.this : key_name => key_resource.versionless_id
  }
}