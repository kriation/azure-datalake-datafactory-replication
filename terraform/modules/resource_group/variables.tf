variable "name" {
  description = "Resource Group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Optional tags to apply to the resource group. Supply sensitive or environment-specific tags from untracked local inputs."
  type        = map(string)
  default     = {}
}
