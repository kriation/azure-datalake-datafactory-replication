resource "azurerm_key_vault" "this" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = var.sku_name
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled
  rbac_authorization_enabled = true

  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    bypass         = var.bypass
    default_action = var.default_action
    ip_rules       = var.ip_rules
  }

  timeouts {
    delete = var.delete_timeout
  }
}

resource "azurerm_private_endpoint" "this" {
  name                = "${var.name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.name}-pe-conn"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "keyvault-zone-group"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
