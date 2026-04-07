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
  default     = true
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

variable "key_vault_bypass" {
  description = "Network ACL bypass mode for regional Key Vaults."
  type        = string
  default     = "None"
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

variable "key_vault_secrets_user_role_definition_name" {
  description = "Role granted to service identities that need Key Vault secret read access."
  type        = string
  default     = "Key Vault Secrets User"
}

variable "key_vault_role_assignment_propagation_wait" {
  description = "Wait duration after Key Vault RBAC assignments before creating data-plane CMKs."
  type        = string
  default     = "30s"
}

variable "storage_min_tls_version" {
  description = "Minimum TLS version for all storage accounts."
  type        = string
  default     = "TLS1_2"
}

variable "storage_public_network_access_enabled" {
  description = "Enable public network access for storage accounts."
  type        = bool
  default     = false
}

variable "create_datalake_filesystems" {
  description = "Whether Data Lake filesystem resources should be created."
  type        = bool
  default     = true
}

variable "data_factory_source_fileshare_connection_secret_name" {
  description = "Secret name in the Canada East Key Vault for the source file share connection string."
  type        = string
  default     = "adf-source-fileshare-connection-string"
}

variable "data_factory_dest_fileshare_connection_secret_name" {
  description = "Secret name in the Canada East Key Vault for the destination file share connection string."
  type        = string
  default     = "adf-dest-fileshare-connection-string"
}

# ---------------------------------------------------------------------------
# Incremental sync checkpoint storage
# ---------------------------------------------------------------------------

variable "canadaeast_checkpoint_storage_name" {
  description = "Storage Account name for the dedicated ADF checkpoint store in Canada East."
  type        = string
  default     = "stdcheckpointcanadaeast"
}

variable "adf_checkpoint_container_name" {
  description = "Blob container name within the checkpoint storage account."
  type        = string
  default     = "adf-checkpoints"
}

variable "adf_checkpoint_journal_prefix" {
  description = "Path prefix for immutable audit journal entries inside the checkpoint container."
  type        = string
  default     = "journal"
}

variable "adf_checkpoint_current_prefix" {
  description = "Path prefix for mutable runtime checkpoint head blobs."
  type        = string
  default     = "current"
}

variable "adf_fileshare_checkpoint_blob_name" {
  description = "Blob name for the file share sync state checkpoint."
  type        = string
  default     = "fileshare-sync-state.json"
}

variable "adf_datalake_checkpoint_blob_name" {
  description = "Blob name for the Data Lake Gen2 sync state checkpoint."
  type        = string
  default     = "datalake-sync-state.json"
}

variable "adf_incremental_bootstrap_watermark" {
  description = "Fallback watermark used on first invocation when no checkpoint blob exists."
  type        = string
  default     = "1970-01-01T00:00:00Z"
}

variable "adf_delete_reconcile_schedule_hours" {
  description = "UTC hours at which the delete-reconciliation triggers fire each day (e.g. [6, 18])."
  type        = list(number)
  default     = [6, 18]
}

variable "adf_delete_reconcile_trigger_start_time" {
  description = "ISO-8601 start time for delete-reconciliation ScheduleTriggers."
  type        = string
  default     = "2026-04-01T06:00:00Z"
}

variable "adf_checkpoint_soft_delete_days" {
  description = "Blob soft-delete retention days for the checkpoint storage account."
  type        = number
  default     = 30
}

variable "adf_checkpoint_version_retention_days" {
  description = "Non-current blob version retention days for the checkpoint storage account."
  type        = number
  default     = 30
}

variable "adf_checkpoint_journal_immutability_days" {
  description = "Time-based immutability retention days applied to the checkpoint journal path."
  type        = number
  default     = 365
}

variable "adf_checkpoint_log_retention_days" {
  description = "Diagnostic log retention days for checkpoint storage audit evidence."
  type        = number
  default     = 365
}

variable "adf_checkpoint_immutability_mode" {
  description = "Immutability operating mode: 'demo-regulated' (unlocked, teardown-safe) or 'strict-regulated' (locked WORM)."
  type        = string
  default     = "demo-regulated"

  validation {
    condition     = contains(["demo-regulated", "strict-regulated"], var.adf_checkpoint_immutability_mode)
    error_message = "adf_checkpoint_immutability_mode must be 'demo-regulated' or 'strict-regulated'."
  }
}
