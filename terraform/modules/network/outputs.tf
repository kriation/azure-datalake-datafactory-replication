output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "vnet_name" {
  value = azurerm_virtual_network.this.name
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_ids" {
  value = { for zone_name, zone in azurerm_private_dns_zone.this : zone_name => zone.id }
}

output "private_dns_zone_names" {
  value = keys(azurerm_private_dns_zone.this)
}
