
# This module now expects Data Factory to be created elsewhere and passed in via variables.
# Only ARM template deployment and pipeline logic should remain here.


resource "azurerm_resource_group_template_deployment" "pipeline" {
  name                = "adf-pipeline-deployment"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/pipeline.json")
  parameters_content = jsonencode({
    factoryName                      = { value = var.data_factory_name },
    keyVaultBaseUrl                  = { value = var.key_vault_uri },
    sourceFileshareAccountName       = { value = var.source_storage_account },
    destFileshareAccountName         = { value = var.dest_storage_account },
    sourceFileshareStorageResourceId = { value = var.source_fileshare_storage_resource_id },
    destFileshareStorageResourceId   = { value = var.dest_fileshare_storage_resource_id },
    sourceDatalakeAccountName        = { value = var.source_datalake_storage_account },
    destDatalakeAccountName          = { value = var.dest_datalake_storage_account },
    sourceDatalakeFilesystem         = { value = var.source_datalake_filesystem_name },
    destDatalakeFilesystem           = { value = var.dest_datalake_filesystem_name },
    # Incremental sync checkpoint parameters
    checkpointStorageAccountName    = { value = var.checkpoint_storage_account_name },
    checkpointStorageResourceId     = { value = var.checkpoint_storage_account_id },
    checkpointContainerName         = { value = var.adf_checkpoint_container_name },
    checkpointCurrentPrefix         = { value = var.adf_checkpoint_current_prefix },
    checkpointJournalPrefix         = { value = var.adf_checkpoint_journal_prefix },
    fileshareCheckpointBlobName     = { value = var.adf_fileshare_checkpoint_blob_name },
    datalakeCheckpointBlobName      = { value = var.adf_datalake_checkpoint_blob_name },
    bootstrapWatermark              = { value = var.adf_incremental_bootstrap_watermark },
    deleteReconcileScheduleHours    = { value = jsonencode(var.adf_delete_reconcile_schedule_hours) },
    deleteReconcileTriggerStartTime = { value = var.adf_delete_reconcile_trigger_start_time }
  })
}

# Example: Linked services and pipeline for file copy (simplified)



# Pipeline and dataset resources would go here
# For a real deployment, use outputs from storage modules for connection strings
