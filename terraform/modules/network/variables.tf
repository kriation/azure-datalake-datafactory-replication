variable "name" {
  description = "Virtual network name"
  type        = string
}

variable "location" {
  description = "Azure region for the network resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that hosts the network resources"
  type        = string
}

variable "address_space" {
  description = "Address space assigned to the VNet"
  type        = list(string)
}

variable "private_endpoint_subnet_name" {
  description = "Name of the private endpoint subnet"
  type        = string
}

variable "private_endpoint_subnet_prefixes" {
  description = "Address prefixes for the private endpoint subnet"
  type        = list(string)
}

variable "private_dns_zone_names" {
  description = "Private DNS zones created and linked to the VNet"
  type        = list(string)
  default = [
    "privatelink.file.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net"
  ]
}
