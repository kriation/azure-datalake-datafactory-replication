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

variable "source_fileshare_connection_secret_name" {
  description = "Secret name for source file share connection string"
  type        = string
}

variable "dest_fileshare_connection_secret_name" {
  description = "Secret name for destination file share connection string"
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
