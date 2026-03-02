variable "source_storage_connection_string" {
  description = "Primary connection string for source storage account"
  type        = string
}

variable "dest_storage_connection_string" {
  description = "Primary connection string for destination storage account"
  type        = string
}
variable "name" {
  description = "Data Factory name"
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

variable "source_storage_account" {
  description = "Source Storage Account name (East US 2)"
  type        = string
}

variable "dest_storage_account" {
  description = "Destination Storage Account name (Canada East)"
  type        = string
}
