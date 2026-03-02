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
