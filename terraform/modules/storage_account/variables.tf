variable "name" {
  description = "Storage Account name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "min_tls_version" {
  description = "Minimum TLS version for the storage account."
  type        = string
  default     = "TLS1_2"
}

variable "public_network_access_enabled" {
  description = "Enable or disable public network access for the storage account."
  type        = bool
  default     = false
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
