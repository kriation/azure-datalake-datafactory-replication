variable "name" {
  description = "Storage Account name for the checkpoint store."
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "container_name" {
  description = "Blob container name for ADF checkpoints."
  type        = string
  default     = "adf-checkpoints"
}

variable "soft_delete_days" {
  description = "Blob soft-delete retention in days."
  type        = number
  default     = 30
}

variable "version_retention_days" {
  description = "Non-current blob version retention in days."
  type        = number
  default     = 30
}

variable "journal_immutability_days" {
  description = "Time-based immutability retention days applied to the journal container path."
  type        = number
  default     = 365
}

variable "immutability_mode" {
  description = "Immutability mode: 'demo-regulated' (unlocked) or 'strict-regulated' (locked WORM)."
  type        = string
  default     = "demo-regulated"

  validation {
    condition     = contains(["demo-regulated", "strict-regulated"], var.immutability_mode)
    error_message = "immutability_mode must be 'demo-regulated' or 'strict-regulated'."
  }
}
