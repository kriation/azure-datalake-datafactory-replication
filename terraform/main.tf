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

module "data_factory" {
  source              = "./modules/data_factory"
  name                = var.data_factory_name
  resource_group_name = module.canadaeast_rg.name
  location            = module.canadaeast_rg.location
  providers = {
    azurerm = azurerm.canadaeast
  }
  source_storage_account = module.eastus2_storage.name
  dest_storage_account   = module.canadaeast_storage.name
  source_storage_connection_string = module.eastus2_storage.primary_connection_string
  dest_storage_connection_string   = module.canadaeast_storage.primary_connection_string
}
