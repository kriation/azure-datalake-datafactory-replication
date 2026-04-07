variable "storage_account_name" {
  description = "The name of the storage account."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
}

variable "location" {
  description = "The Azure region."
  type        = string
}

variable "filesystem_name" {
  description = "The name of the Data Lake Gen2 filesystem (container)."
  type        = string
}

variable "min_tls_version" {
  description = "Minimum TLS version for the Data Lake storage account."
  type        = string
  default     = "TLS1_2"
}

variable "public_network_access_enabled" {
  description = "Enable or disable public network access for the Data Lake storage account."
  type        = bool
  default     = false
}

variable "filesystem_create_wait" {
  description = "Delay before filesystem operations to allow storage network/public-access changes to propagate to the DFS endpoint."
  type        = string
  default     = "45s"
}

variable "create_filesystem" {
  description = "Whether to create the Data Lake filesystem resource."
  type        = bool
  default     = true
}

variable "soft_delete_days" {
  description = "Blob soft-delete retention in days. Set to 0 to disable."
  type        = number
  default     = 0
}

variable "versioning_enabled" {
  description = "Enable blob versioning."
  type        = bool
  default     = false
}

variable "change_feed_enabled" {
  description = "Enable blob change feed for audit traceability."
  type        = bool
  default     = false
}
