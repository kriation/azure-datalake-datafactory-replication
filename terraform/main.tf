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
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
  required_version = ">= 1.0"
}

provider "azurerm" {
  features {}
}

provider "azurerm" {
  alias           = "eastus2"
  features        {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azurerm" {
  alias           = "canadaeast"
  features        {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

module "eastus2_rg" {
  source   = "./modules/resource_group"
  name     = var.eastus2_rg_name
  location = "eastus2"
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_rg" {
  source   = "./modules/resource_group"
  name     = var.canadaeast_rg_name
  location = "canadaeast"
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

module "eastus2_storage" {
  source              = "./modules/storage_account"
  name                = var.eastus2_storage_name
  resource_group_name = module.eastus2_rg.name
  location            = module.eastus2_rg.location
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_storage" {
  source              = "./modules/storage_account"
  name                = var.canadaeast_storage_name
  resource_group_name = module.canadaeast_rg.name
  location            = module.canadaeast_rg.location
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

# Data Factory (pipelines, ARM, role assignments)
module "data_factory" {
  source              = "./modules/data_factory"
  data_factory_id     = module.data_factory_identity.id
  data_factory_name   = module.data_factory_identity.name
  data_factory_principal_id = module.data_factory_identity.principal_id
  source_storage_account = module.eastus2_storage.name
  dest_storage_account   = module.canadaeast_storage.name
  source_storage_connection_string = module.eastus2_storage.primary_connection_string
  dest_storage_connection_string   = module.canadaeast_storage.primary_connection_string
  source_datalake_storage_account = module.eastus2_datalake.storage_account_name
  dest_datalake_storage_account   = module.canadaeast_datalake.storage_account_name
  resource_group_name = module.canadaeast_rg.name
  source_datalake_filesystem_name = module.eastus2_datalake.filesystem_name
  dest_datalake_filesystem_name   = module.canadaeast_datalake.filesystem_name
  providers = {
    azurerm = azurerm.canadaeast
  }
}

# Data Lake Gen2 Storage Accounts and Filesystems
module "eastus2_datalake" {
  source                = "./modules/storage_account_datalake"
  storage_account_name  = var.eastus2_datalake_storage_name
  resource_group_name   = module.eastus2_rg.name
  location              = module.eastus2_rg.location
  filesystem_name       = var.eastus2_datalake_filesystem_name
  providers = {
    azurerm = azurerm.eastus2
  }
}

module "canadaeast_datalake" {
  source                = "./modules/storage_account_datalake"
  storage_account_name  = var.canadaeast_datalake_storage_name
  resource_group_name   = module.canadaeast_rg.name
  location              = module.canadaeast_rg.location
  filesystem_name       = var.canadaeast_datalake_filesystem_name
  providers = {
    azurerm = azurerm.canadaeast
  }
}
