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
