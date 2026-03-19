variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure Tenant ID"
  type        = string
}

variable "eastus2_rg_name" {
  default     = "demo-eastus2-rg"
  description = "Resource Group name for East US 2"
}

variable "canadaeast_rg_name" {
  default     = "demo-canadaeast-rg"
  description = "Resource Group name for Canada East"
}

variable "eastus2_storage_name" {
  default     = "demoeastus2storage"
  description = "Storage Account name for East US 2"
}

variable "canadaeast_storage_name" {
  default     = "democanadaeaststorage"
  description = "Storage Account name for Canada East"
}

variable "data_factory_name" {
  default     = "demo-datafactory"
  description = "Azure Data Factory name"
}

variable "eastus2_datalake_storage_name" {
  default     = "dldemoeastus2"
  description = "Data Lake Gen2 Storage Account name for East US 2"
}

variable "canadaeast_datalake_storage_name" {
  default     = "dldemocanadaeast"
  description = "Data Lake Gen2 Storage Account name for Canada East"
}

variable "eastus2_datalake_filesystem_name" {
  default     = "demo-filesystem"
  description = "Data Lake Gen2 Filesystem name for East US 2"
}

variable "canadaeast_datalake_filesystem_name" {
  default     = "demo-filesystem"
  description = "Data Lake Gen2 Filesystem name for Canada East"
}

variable "eastus2_vnet_name" {
  default     = "vnet-demo-eastus2"
  description = "Virtual Network name for East US 2"
}

variable "canadaeast_vnet_name" {
  default     = "vnet-demo-canadaeast"
  description = "Virtual Network name for Canada East"
}

variable "eastus2_vnet_address_space" {
  description = "Address space for East US 2 VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "canadaeast_vnet_address_space" {
  description = "Address space for Canada East VNet"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "eastus2_private_endpoint_subnet_name" {
  default     = "snet-private-endpoints"
  description = "Private endpoint subnet name for East US 2"
}

variable "canadaeast_private_endpoint_subnet_name" {
  default     = "snet-private-endpoints"
  description = "Private endpoint subnet name for Canada East"
}

variable "eastus2_private_endpoint_subnet_prefixes" {
  description = "Address prefixes for East US 2 private endpoint subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "canadaeast_private_endpoint_subnet_prefixes" {
  description = "Address prefixes for Canada East private endpoint subnet"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

variable "private_dns_zone_names" {
  description = "Private DNS zones linked to each regional VNet"
  type        = list(string)
  default = [
    "privatelink.file.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net"
  ]
}
