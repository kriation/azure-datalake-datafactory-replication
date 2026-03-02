resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags = {
    SecurityControl = "Ignore"
  }
}

output "name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}
