variable "key_vault_id" {
  description = "The Key Vault ID that will store the CMKs."
  type        = string
}

variable "key_names" {
  description = "The CMK names to create in the target Key Vault."
  type        = list(string)
}

variable "key_type" {
  description = "The Key Vault key type used for CMKs."
  type        = string
  default     = "RSA-HSM"
}

variable "key_size" {
  description = "The RSA key size for CMKs."
  type        = number
  default     = 2048
}