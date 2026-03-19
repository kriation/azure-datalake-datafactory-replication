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

variable "resource_group_tags" {
  description = "Optional tags applied to regional resource groups. Keep sensitive or internal-only values in untracked local tfvars files."
  type        = map(string)
  default     = {}
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

variable "eastus2_key_vault_name" {
  description = "Key Vault name for East US 2"
  type        = string
  default     = "kvdemoeastus2"
}

variable "canadaeast_key_vault_name" {
  description = "Key Vault name for Canada East"
  type        = string
  default     = "kvdemocanadaeast"
}

variable "key_vault_sku_name" {
  description = "SKU tier for regional Key Vaults"
  type        = string
  default     = "premium"
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention in days for regional Key Vaults (minimum 7 in Azure)"
  type        = number
  default     = 7
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for regional Key Vaults"
  type        = bool
  default     = false
}

variable "key_vault_public_network_access_enabled" {
  description = "Enable public network access for regional Key Vaults"
  type        = bool
  default     = false
}

variable "key_vault_ip_rules" {
  description = "Optional CIDRs allowed to access regional Key Vault public endpoint"
  type        = list(string)
  default     = []
}

variable "eastus2_storage_cmk_name" {
  description = "CMK name for the East US 2 file share storage account."
  type        = string
  default     = "cmk-st-eastus2"
}

variable "eastus2_datalake_cmk_name" {
  description = "CMK name for the East US 2 Data Lake storage account."
  type        = string
  default     = "cmk-dl-eastus2"
}

variable "canadaeast_storage_cmk_name" {
  description = "CMK name for the Canada East file share storage account."
  type        = string
  default     = "cmk-st-canadaeast"
}

variable "canadaeast_datalake_cmk_name" {
  description = "CMK name for the Canada East Data Lake storage account."
  type        = string
  default     = "cmk-dl-canadaeast"
}

variable "canadaeast_data_factory_cmk_name" {
  description = "CMK name for the Canada East Data Factory instance."
  type        = string
  default     = "cmk-adf-canadaeast"
}

variable "key_vault_cmk_key_type" {
  description = "Key Vault key type used for CMKs."
  type        = string
  default     = "RSA-HSM"
}

variable "key_vault_cmk_key_size" {
  description = "Key size used for CMKs."
  type        = number
  default     = 2048
}

variable "key_vault_admin_role_definition_name" {
  description = "Role granted to the deploying principal so Terraform can manage keys in RBAC-enabled vaults."
  type        = string
  default     = "Key Vault Administrator"
}

variable "key_vault_crypto_user_role_definition_name" {
  description = "Role granted to service identities that need CMK crypto operations."
  type        = string
  default     = "Key Vault Crypto Service Encryption User"
}

variable "key_vault_role_assignment_propagation_wait" {
  description = "Wait duration after Key Vault RBAC assignments before creating data-plane CMKs."
  type        = string
  default     = "30s"
}
