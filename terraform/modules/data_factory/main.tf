resource "azurerm_resource_group_template_deployment" "pipeline" {
  name                = "adf-pipeline-deployment"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/pipeline.json")
  parameters_content  = jsonencode({
    factoryName = { value = azurerm_data_factory.this.name },
    sourceConnectionString = { value = var.source_storage_connection_string },
    destConnectionString   = { value = var.dest_storage_connection_string }
  })
}
resource "azurerm_data_factory" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Example: Linked services and pipeline for file copy (simplified)
resource "azurerm_data_factory_linked_service_azure_file_storage" "source" {
  name              = "source-fileshare"
  data_factory_id   = azurerm_data_factory.this.id
  connection_string = var.source_storage_connection_string
}

resource "azurerm_data_factory_linked_service_azure_file_storage" "dest" {
  name              = "dest-fileshare"
  data_factory_id   = azurerm_data_factory.this.id
  connection_string = var.dest_storage_connection_string
}

# Pipeline and dataset resources would go here
# For a real deployment, use outputs from storage modules for connection strings
