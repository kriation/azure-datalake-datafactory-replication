variable "source_datalake_filesystem_name" {
  description = "Name of the source Data Lake Gen2 filesystem (East US 2)"
  type        = string
}

variable "dest_datalake_filesystem_name" {
  description = "Name of the destination Data Lake Gen2 filesystem (Canada East)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group name for Data Factory deployment"
  type        = string
}

variable "key_vault_uri" {
  description = "Vault URI used by the Data Factory Key Vault linked service"
  type        = string
}

variable "source_storage_account" {
  description = "Source Storage Account name (East US 2)"
  type        = string
}

variable "dest_storage_account" {
  description = "Destination Storage Account name (Canada East)"
  type        = string
}

variable "source_fileshare_storage_resource_id" {
  description = "Resource ID of the source file share storage account"
  type        = string
}

variable "dest_fileshare_storage_resource_id" {
  description = "Resource ID of the destination file share storage account"
  type        = string
}

variable "source_datalake_storage_account" {
  description = "Source Data Lake Gen2 Storage Account name (East US 2)"
  type        = string
}

variable "dest_datalake_storage_account" {
  description = "Destination Data Lake Gen2 Storage Account name (Canada East)"
  type        = string
}


variable "data_factory_id" {
  description = "ID of the Data Factory instance"
  type        = string
}

variable "data_factory_name" {
  description = "Name of the Data Factory instance"
  type        = string
}

variable "data_factory_principal_id" {
  description = "Principal ID of the Data Factory managed identity"
  type        = string
}

# ---------------------------------------------------------------------------
# Incremental sync checkpoint variables
# ---------------------------------------------------------------------------

variable "checkpoint_storage_account_name" {
  description = "Name of the dedicated checkpoint storage account."
  type        = string
}

variable "checkpoint_storage_account_id" {
  description = "Resource ID of the dedicated checkpoint storage account."
  type        = string
}

variable "adf_checkpoint_container_name" {
  description = "Blob container name within the checkpoint storage account."
  type        = string
  default     = "adf-checkpoints"
}

variable "adf_checkpoint_current_prefix" {
  description = "Path prefix for mutable runtime checkpoint head blobs."
  type        = string
  default     = "current"
}

variable "adf_checkpoint_journal_prefix" {
  description = "Path prefix for immutable audit journal entries."
  type        = string
  default     = "journal"
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
  description = "Fallback watermark for first pipeline run when no checkpoint exists."
  type        = string
  default     = "1970-01-01T00:00:00Z"
}

variable "adf_delete_reconcile_schedule_hours" {
  description = "UTC hours at which the delete-reconciliation triggers fire each day."
  type        = list(number)
  default     = [6, 18]
}

variable "adf_delete_reconcile_trigger_start_time" {
  description = "ISO-8601 start time for delete-reconciliation ScheduleTriggers."
  type        = string
  default     = "2026-04-01T06:00:00Z"
}
