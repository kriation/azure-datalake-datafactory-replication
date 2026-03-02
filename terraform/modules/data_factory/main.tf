
# This module now expects Data Factory to be created elsewhere and passed in via variables.
# Only ARM template deployment and pipeline logic should remain here.


resource "azurerm_resource_group_template_deployment" "pipeline" {
  name                = "adf-pipeline-deployment"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/pipeline.json")
  parameters_content  = jsonencode({
    factoryName = { value = var.data_factory_name },
    sourceConnectionString = { value = var.source_storage_connection_string },
    destConnectionString   = { value = var.dest_storage_connection_string },
    sourceDatalakeAccountName = { value = var.source_datalake_storage_account },
    destDatalakeAccountName   = { value = var.dest_datalake_storage_account },
    sourceDatalakeFilesystem  = { value = var.source_datalake_filesystem_name },
    destDatalakeFilesystem    = { value = var.dest_datalake_filesystem_name }
  })
}

# Example: Linked services and pipeline for file copy (simplified)



# Pipeline and dataset resources would go here
# For a real deployment, use outputs from storage modules for connection strings
