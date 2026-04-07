# Assign Storage Blob Data Contributor role to Data Factory MI on both Data Lake Gen2 storage accounts
resource "azurerm_role_assignment" "adf_to_eastus2_datalake" {
  scope                = module.eastus2_datalake.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.data_factory_identity.principal_id
}

resource "azurerm_role_assignment" "adf_to_canadaeast_datalake" {
  scope                = module.canadaeast_datalake.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.data_factory_identity.principal_id
}

# Azure Files RBAC: ADF managed identity needs data-plane access to both fileshare storage accounts
resource "azurerm_role_assignment" "adf_to_eastus2_fileshare" {
  scope                = module.eastus2_storage.id
  role_definition_name = "Storage File Data Privileged Reader"
  principal_id         = module.data_factory_identity.principal_id
}

resource "azurerm_role_assignment" "adf_to_canadaeast_fileshare" {
  scope                = module.canadaeast_storage.id
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = module.data_factory_identity.principal_id
}
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
  required_version = ">= 1.0"
}

provider "azurerm" {
  features {}
}

provider "azurerm" {
  alias = "eastus2"
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azurerm" {
  alias = "canadaeast"
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

data "azurerm_client_config" "current" {}

module "eastus2_rg" {
  source   = "./modules/resource_group"
  name     = var.eastus2_rg_name
  location = "eastus2"
  tags     = var.resource_group_tags
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_rg" {
  source   = "./modules/resource_group"
  name     = var.canadaeast_rg_name
  location = "canadaeast"
  tags     = var.resource_group_tags
  providers = {
    azurerm = azurerm.canadaeast
  }
}

module "eastus2_network" {
  source                           = "./modules/network"
  name                             = var.eastus2_vnet_name
  resource_group_name              = module.eastus2_rg.name
  location                         = module.eastus2_rg.location
  address_space                    = var.eastus2_vnet_address_space
  private_endpoint_subnet_name     = var.eastus2_private_endpoint_subnet_name
  private_endpoint_subnet_prefixes = var.eastus2_private_endpoint_subnet_prefixes
  private_dns_zone_names           = var.private_dns_zone_names
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_network" {
  source                           = "./modules/network"
  name                             = var.canadaeast_vnet_name
  resource_group_name              = module.canadaeast_rg.name
  location                         = module.canadaeast_rg.location
  address_space                    = var.canadaeast_vnet_address_space
  private_endpoint_subnet_name     = var.canadaeast_private_endpoint_subnet_name
  private_endpoint_subnet_prefixes = var.canadaeast_private_endpoint_subnet_prefixes
  private_dns_zone_names           = var.private_dns_zone_names
  providers = {
    azurerm = azurerm.canadaeast
  }
}

module "eastus2_key_vault" {
  source                        = "./modules/key_vault"
  name                          = var.eastus2_key_vault_name
  location                      = module.eastus2_rg.location
  resource_group_name           = module.eastus2_rg.name
  tenant_id                     = var.tenant_id
  private_endpoint_subnet_id    = module.eastus2_network.private_endpoint_subnet_id
  private_dns_zone_id           = module.eastus2_network.private_dns_zone_ids["privatelink.vaultcore.azure.net"]
  sku_name                      = var.key_vault_sku_name
  soft_delete_retention_days    = var.key_vault_soft_delete_retention_days
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  public_network_access_enabled = var.key_vault_public_network_access_enabled
  bypass                        = var.key_vault_bypass
  ip_rules                      = var.key_vault_ip_rules
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_key_vault" {
  source                        = "./modules/key_vault"
  name                          = var.canadaeast_key_vault_name
  location                      = module.canadaeast_rg.location
  resource_group_name           = module.canadaeast_rg.name
  tenant_id                     = var.tenant_id
  private_endpoint_subnet_id    = module.canadaeast_network.private_endpoint_subnet_id
  private_dns_zone_id           = module.canadaeast_network.private_dns_zone_ids["privatelink.vaultcore.azure.net"]
  sku_name                      = var.key_vault_sku_name
  soft_delete_retention_days    = var.key_vault_soft_delete_retention_days
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  public_network_access_enabled = var.key_vault_public_network_access_enabled
  bypass                        = var.key_vault_bypass
  ip_rules                      = var.key_vault_ip_rules
  providers = {
    azurerm = azurerm.canadaeast
  }
}

module "eastus2_storage" {
  source                        = "./modules/storage_account"
  name                          = var.eastus2_storage_name
  resource_group_name           = module.eastus2_rg.name
  location                      = module.eastus2_rg.location
  min_tls_version               = var.storage_min_tls_version
  public_network_access_enabled = var.storage_public_network_access_enabled
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_storage" {
  source                        = "./modules/storage_account"
  name                          = var.canadaeast_storage_name
  resource_group_name           = module.canadaeast_rg.name
  location                      = module.canadaeast_rg.location
  min_tls_version               = var.storage_min_tls_version
  public_network_access_enabled = var.storage_public_network_access_enabled
  providers = {
    azurerm = azurerm.canadaeast
  }
}


# Data Factory Identity Module
module "data_factory_identity" {
  source              = "./modules/data_factory_identity"
  name                = var.data_factory_name
  resource_group_name = module.canadaeast_rg.name
  location            = module.canadaeast_rg.location
  providers = {
    azurerm = azurerm.canadaeast
  }
}

resource "azurerm_role_assignment" "eastus2_key_vault_admin_current" {
  scope                = module.eastus2_key_vault.id
  role_definition_name = var.key_vault_admin_role_definition_name
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "canadaeast_key_vault_admin_current" {
  scope                = module.canadaeast_key_vault.id
  role_definition_name = var.key_vault_admin_role_definition_name
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "canadaeast_data_factory_key_vault_crypto_user" {
  scope                = module.canadaeast_key_vault.id
  role_definition_name = var.key_vault_crypto_user_role_definition_name
  principal_id         = module.data_factory_identity.principal_id
}

resource "azurerm_role_assignment" "canadaeast_data_factory_key_vault_secrets_user" {
  scope                = module.canadaeast_key_vault.id
  role_definition_name = var.key_vault_secrets_user_role_definition_name
  principal_id         = module.data_factory_identity.principal_id
}

resource "time_sleep" "eastus2_key_vault_rbac_propagation" {
  create_duration = var.key_vault_role_assignment_propagation_wait

  depends_on = [
    azurerm_role_assignment.eastus2_key_vault_admin_current,
  ]
}

resource "time_sleep" "canadaeast_key_vault_rbac_propagation" {
  create_duration = var.key_vault_role_assignment_propagation_wait

  depends_on = [
    azurerm_role_assignment.canadaeast_key_vault_admin_current,
    azurerm_role_assignment.canadaeast_data_factory_key_vault_crypto_user,
    azurerm_role_assignment.canadaeast_data_factory_key_vault_secrets_user,
  ]
}

resource "azurerm_key_vault_secret" "adf_source_fileshare_connection_string" {
  name         = var.data_factory_source_fileshare_connection_secret_name
  value        = module.eastus2_storage.primary_connection_string
  key_vault_id = module.canadaeast_key_vault.id

  depends_on = [
    time_sleep.canadaeast_key_vault_rbac_propagation,
  ]
}

resource "azurerm_key_vault_secret" "adf_dest_fileshare_connection_string" {
  name         = var.data_factory_dest_fileshare_connection_secret_name
  value        = module.canadaeast_storage.primary_connection_string
  key_vault_id = module.canadaeast_key_vault.id

  depends_on = [
    time_sleep.canadaeast_key_vault_rbac_propagation,
  ]
}

module "eastus2_encryption_keys" {
  source       = "./modules/encryption_keys"
  key_vault_id = module.eastus2_key_vault.id
  key_names = [
    var.eastus2_storage_cmk_name,
    var.eastus2_datalake_cmk_name,
  ]
  key_type = var.key_vault_cmk_key_type
  key_size = var.key_vault_cmk_key_size
  providers = {
    azurerm = azurerm.eastus2
  }
  depends_on = [
    time_sleep.eastus2_key_vault_rbac_propagation,
  ]
}

module "canadaeast_encryption_keys" {
  source       = "./modules/encryption_keys"
  key_vault_id = module.canadaeast_key_vault.id
  key_names = [
    var.canadaeast_storage_cmk_name,
    var.canadaeast_datalake_cmk_name,
    var.canadaeast_data_factory_cmk_name,
  ]
  key_type = var.key_vault_cmk_key_type
  key_size = var.key_vault_cmk_key_size
  providers = {
    azurerm = azurerm.canadaeast
  }
  depends_on = [
    time_sleep.canadaeast_key_vault_rbac_propagation,
  ]
}

# Data Factory (pipelines, ARM, role assignments)
module "data_factory" {
  source                               = "./modules/data_factory"
  data_factory_id                      = module.data_factory_identity.id
  data_factory_name                    = module.data_factory_identity.name
  data_factory_principal_id            = module.data_factory_identity.principal_id
  source_storage_account               = module.eastus2_storage.name
  dest_storage_account                 = module.canadaeast_storage.name
  source_fileshare_storage_resource_id = module.eastus2_storage.id
  dest_fileshare_storage_resource_id   = module.canadaeast_storage.id
  key_vault_uri                        = module.canadaeast_key_vault.vault_uri
  source_datalake_storage_account      = module.eastus2_datalake.storage_account_name
  dest_datalake_storage_account        = module.canadaeast_datalake.storage_account_name
  resource_group_name                  = module.canadaeast_rg.name
  source_datalake_filesystem_name      = module.eastus2_datalake.filesystem_name
  dest_datalake_filesystem_name        = module.canadaeast_datalake.filesystem_name
  # Checkpoint storage wiring for incremental sync
  checkpoint_storage_account_name         = module.canadaeast_checkpoint_storage.name
  checkpoint_storage_account_id           = module.canadaeast_checkpoint_storage.id
  adf_checkpoint_container_name           = var.adf_checkpoint_container_name
  adf_checkpoint_current_prefix           = var.adf_checkpoint_current_prefix
  adf_checkpoint_journal_prefix           = var.adf_checkpoint_journal_prefix
  adf_fileshare_checkpoint_blob_name      = var.adf_fileshare_checkpoint_blob_name
  adf_datalake_checkpoint_blob_name       = var.adf_datalake_checkpoint_blob_name
  adf_incremental_bootstrap_watermark     = var.adf_incremental_bootstrap_watermark
  adf_delete_reconcile_schedule_hours     = var.adf_delete_reconcile_schedule_hours
  adf_delete_reconcile_trigger_start_time = var.adf_delete_reconcile_trigger_start_time
  providers = {
    azurerm = azurerm.canadaeast
  }

  depends_on = [
    azurerm_data_factory_customer_managed_key.canadaeast_data_factory_cmk_binding,
    azurerm_role_assignment.adf_to_eastus2_fileshare,
    azurerm_role_assignment.adf_to_canadaeast_fileshare,
    azurerm_role_assignment.adf_to_checkpoint_storage,
    module.canadaeast_checkpoint_storage,
  ]
}

resource "azurerm_data_factory_customer_managed_key" "canadaeast_data_factory_cmk_binding" {
  data_factory_id         = module.data_factory_identity.id
  customer_managed_key_id = module.canadaeast_encryption_keys.key_ids[var.canadaeast_data_factory_cmk_name]

  depends_on = [
    module.data_factory_identity,
    module.canadaeast_encryption_keys,
    time_sleep.canadaeast_key_vault_rbac_propagation,
  ]
}

# Data Lake Gen2 Storage Accounts and Filesystems
module "eastus2_datalake" {
  source                        = "./modules/storage_account_datalake"
  storage_account_name          = var.eastus2_datalake_storage_name
  resource_group_name           = module.eastus2_rg.name
  location                      = module.eastus2_rg.location
  filesystem_name               = var.eastus2_datalake_filesystem_name
  create_filesystem             = var.create_datalake_filesystems
  min_tls_version               = var.storage_min_tls_version
  public_network_access_enabled = var.storage_public_network_access_enabled
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_datalake" {
  source                        = "./modules/storage_account_datalake"
  storage_account_name          = var.canadaeast_datalake_storage_name
  resource_group_name           = module.canadaeast_rg.name
  location                      = module.canadaeast_rg.location
  filesystem_name               = var.canadaeast_datalake_filesystem_name
  create_filesystem             = var.create_datalake_filesystems
  min_tls_version               = var.storage_min_tls_version
  public_network_access_enabled = var.storage_public_network_access_enabled
  providers = {
    azurerm = azurerm.canadaeast
  }
}

# Dedicated checkpoint storage account for ADF incremental sync cursors
module "canadaeast_checkpoint_storage" {
  source                    = "./modules/checkpoint_storage_account"
  name                      = var.canadaeast_checkpoint_storage_name
  resource_group_name       = module.canadaeast_rg.name
  location                  = module.canadaeast_rg.location
  container_name            = var.adf_checkpoint_container_name
  soft_delete_days          = var.adf_checkpoint_soft_delete_days
  version_retention_days    = var.adf_checkpoint_version_retention_days
  journal_immutability_days = var.adf_checkpoint_journal_immutability_days
  immutability_mode         = var.adf_checkpoint_immutability_mode
  providers = {
    azurerm = azurerm.canadaeast
  }
}

# Grant ADF MI Storage Blob Data Contributor on checkpoint storage account (isolated from workload storage)
resource "azurerm_role_assignment" "adf_to_checkpoint_storage" {
  scope                = module.canadaeast_checkpoint_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.data_factory_identity.principal_id
}

resource "azurerm_role_assignment" "eastus2_storage_key_vault_crypto_user" {
  scope                = module.eastus2_key_vault.id
  role_definition_name = var.key_vault_crypto_user_role_definition_name
  principal_id         = module.eastus2_storage.principal_id
}

resource "azurerm_role_assignment" "eastus2_datalake_key_vault_crypto_user" {
  scope                = module.eastus2_key_vault.id
  role_definition_name = var.key_vault_crypto_user_role_definition_name
  principal_id         = module.eastus2_datalake.principal_id
}

resource "azurerm_role_assignment" "canadaeast_storage_key_vault_crypto_user" {
  scope                = module.canadaeast_key_vault.id
  role_definition_name = var.key_vault_crypto_user_role_definition_name
  principal_id         = module.canadaeast_storage.principal_id
}

resource "azurerm_role_assignment" "canadaeast_datalake_key_vault_crypto_user" {
  scope                = module.canadaeast_key_vault.id
  role_definition_name = var.key_vault_crypto_user_role_definition_name
  principal_id         = module.canadaeast_datalake.principal_id
}

resource "time_sleep" "storage_key_vault_rbac_propagation" {
  create_duration = var.key_vault_role_assignment_propagation_wait

  depends_on = [
    azurerm_role_assignment.eastus2_storage_key_vault_crypto_user,
    azurerm_role_assignment.eastus2_datalake_key_vault_crypto_user,
    azurerm_role_assignment.canadaeast_storage_key_vault_crypto_user,
    azurerm_role_assignment.canadaeast_datalake_key_vault_crypto_user,
  ]
}

resource "azurerm_storage_account_customer_managed_key" "eastus2_storage_cmk_binding" {
  storage_account_id = module.eastus2_storage.id
  key_vault_key_id   = module.eastus2_encryption_keys.versionless_key_ids[var.eastus2_storage_cmk_name]

  depends_on = [
    time_sleep.storage_key_vault_rbac_propagation,
    module.eastus2_encryption_keys,
  ]
}

resource "azurerm_storage_account_customer_managed_key" "eastus2_datalake_cmk_binding" {
  storage_account_id = module.eastus2_datalake.storage_account_id
  key_vault_key_id   = module.eastus2_encryption_keys.versionless_key_ids[var.eastus2_datalake_cmk_name]

  depends_on = [
    time_sleep.storage_key_vault_rbac_propagation,
    module.eastus2_encryption_keys,
  ]
}

resource "azurerm_storage_account_customer_managed_key" "canadaeast_storage_cmk_binding" {
  storage_account_id = module.canadaeast_storage.id
  key_vault_key_id   = module.canadaeast_encryption_keys.versionless_key_ids[var.canadaeast_storage_cmk_name]

  depends_on = [
    time_sleep.storage_key_vault_rbac_propagation,
    module.canadaeast_encryption_keys,
  ]
}

resource "azurerm_storage_account_customer_managed_key" "canadaeast_datalake_cmk_binding" {
  storage_account_id = module.canadaeast_datalake.storage_account_id
  key_vault_key_id   = module.canadaeast_encryption_keys.versionless_key_ids[var.canadaeast_datalake_cmk_name]

  depends_on = [
    time_sleep.storage_key_vault_rbac_propagation,
    module.canadaeast_encryption_keys,
  ]
}
