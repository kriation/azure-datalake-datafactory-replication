output "eastus2_rg_name" {
  value = module.eastus2_rg.name
}

output "canadaeast_rg_name" {
  value = module.canadaeast_rg.name
}

output "eastus2_vnet_name" {
  value = module.eastus2_network.vnet_name
}

output "canadaeast_vnet_name" {
  value = module.canadaeast_network.vnet_name
}

output "eastus2_private_endpoint_subnet_id" {
  value = module.eastus2_network.private_endpoint_subnet_id
}

output "canadaeast_private_endpoint_subnet_id" {
  value = module.canadaeast_network.private_endpoint_subnet_id
}

output "eastus2_private_dns_zone_names" {
  value = module.eastus2_network.private_dns_zone_names
}

output "canadaeast_private_dns_zone_names" {
  value = module.canadaeast_network.private_dns_zone_names
}

output "eastus2_key_vault_name" {
  value = module.eastus2_key_vault.name
}

output "canadaeast_key_vault_name" {
  value = module.canadaeast_key_vault.name
}

output "eastus2_key_vault_uri" {
  value = module.eastus2_key_vault.vault_uri
}

output "canadaeast_key_vault_uri" {
  value = module.canadaeast_key_vault.vault_uri
}

output "eastus2_key_vault_private_endpoint_id" {
  value = module.eastus2_key_vault.private_endpoint_id
}

output "canadaeast_key_vault_private_endpoint_id" {
  value = module.canadaeast_key_vault.private_endpoint_id
}

output "current_operator_object_id" {
  value = data.azurerm_client_config.current.object_id
}

output "data_factory_principal_id" {
  value = module.data_factory_identity.principal_id
}

output "key_vault_admin_role_definition_name" {
  value = var.key_vault_admin_role_definition_name
}

output "key_vault_crypto_user_role_definition_name" {
  value = var.key_vault_crypto_user_role_definition_name
}

output "eastus2_storage_cmk_key_id" {
  value = try(module.eastus2_encryption_keys.versionless_key_ids[var.eastus2_storage_cmk_name], null)
}

output "eastus2_datalake_cmk_key_id" {
  value = try(module.eastus2_encryption_keys.versionless_key_ids[var.eastus2_datalake_cmk_name], null)
}

output "canadaeast_storage_cmk_key_id" {
  value = try(module.canadaeast_encryption_keys.versionless_key_ids[var.canadaeast_storage_cmk_name], null)
}

output "canadaeast_datalake_cmk_key_id" {
  value = try(module.canadaeast_encryption_keys.versionless_key_ids[var.canadaeast_datalake_cmk_name], null)
}

output "canadaeast_data_factory_cmk_key_id" {
  value = try(module.canadaeast_encryption_keys.key_ids[var.canadaeast_data_factory_cmk_name], null)
}

output "eastus2_storage_public_network_access_enabled" {
  value = module.eastus2_storage.public_network_access_enabled
}

output "canadaeast_storage_public_network_access_enabled" {
  value = module.canadaeast_storage.public_network_access_enabled
}

output "eastus2_datalake_public_network_access_enabled" {
  value = module.eastus2_datalake.public_network_access_enabled
}

output "canadaeast_datalake_public_network_access_enabled" {
  value = module.canadaeast_datalake.public_network_access_enabled
}

output "eastus2_storage_min_tls_version" {
  value = module.eastus2_storage.min_tls_version
}

output "canadaeast_storage_min_tls_version" {
  value = module.canadaeast_storage.min_tls_version
}

output "eastus2_datalake_min_tls_version" {
  value = module.eastus2_datalake.min_tls_version
}

output "canadaeast_datalake_min_tls_version" {
  value = module.canadaeast_datalake.min_tls_version
}

output "eastus2_storage_cmk_binding_id" {
  value = azurerm_storage_account_customer_managed_key.eastus2_storage_cmk_binding.id
}

output "eastus2_datalake_cmk_binding_id" {
  value = azurerm_storage_account_customer_managed_key.eastus2_datalake_cmk_binding.id
}

output "canadaeast_storage_cmk_binding_id" {
  value = azurerm_storage_account_customer_managed_key.canadaeast_storage_cmk_binding.id
}

output "canadaeast_datalake_cmk_binding_id" {
  value = azurerm_storage_account_customer_managed_key.canadaeast_datalake_cmk_binding.id
}

output "canadaeast_data_factory_cmk_binding_id" {
  value = azurerm_data_factory_customer_managed_key.canadaeast_data_factory_cmk_binding.id
}

output "adf_source_fileshare_connection_secret_name" {
  value = azurerm_key_vault_secret.adf_source_fileshare_connection_string.name
}

output "adf_dest_fileshare_connection_secret_name" {
  value = azurerm_key_vault_secret.adf_dest_fileshare_connection_string.name
}

output "eastus2_storage_name" {
  value = module.eastus2_storage.name
}

output "canadaeast_storage_name" {
  value = module.canadaeast_storage.name
}

output "data_factory_name" {
  value = module.data_factory.name
}

output "eastus2_datalake_storage_name" {
  value = module.eastus2_datalake.storage_account_name
}

output "canadaeast_datalake_storage_name" {
  value = module.canadaeast_datalake.storage_account_name
}

output "eastus2_datalake_filesystem_name" {
  value = module.eastus2_datalake.filesystem_name
}

output "canadaeast_datalake_filesystem_name" {
  value = module.canadaeast_datalake.filesystem_name
}
