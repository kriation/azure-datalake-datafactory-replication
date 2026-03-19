variable "name" {
  description = "Key Vault name"
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for Key Vault resources"
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID used for Key Vault private endpoint"
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ID for privatelink.vaultcore.azure.net"
  type        = string
}

variable "sku_name" {
  description = "Key Vault SKU"
  type        = string
  default     = "premium"
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention period in days"
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "Enable purge protection"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Enable or disable public network access"
  type        = bool
  default     = false
}

variable "bypass" {
  description = "Network ACL bypass mode"
  type        = string
  default     = "None"
}

variable "default_action" {
  description = "Network ACL default action"
  type        = string
  default     = "Deny"
}

variable "ip_rules" {
  description = "Optional public IP CIDRs allowed to access Key Vault"
  type        = list(string)
  default     = []
}

variable "delete_timeout" {
  description = "Timeout for Key Vault delete operations. Short values speed up demo teardown when Azure ARM finalization lags; demo default is 5 minutes."
  type        = string
  default     = "5m"
}
