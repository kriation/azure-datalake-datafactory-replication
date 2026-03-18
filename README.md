# Azure Datalake Object Replication with Azure Data Factory

This Terraform configuration deploys:
- Two resource groups (East US 2 and Canada East)
- Azure Storage Accounts with File Shares (Samba/SMB enabled) and Data Lake Gen2 in both regions
- Azure Data Factory in Canada East to sync file shares and Data Lake Gen2 between regions
- Data Factory Managed Virtual Network integration runtime with managed private endpoints to all source and destination storage endpoints (Azure Files + Data Lake Gen2)
- Scheduled Data Factory pipeline triggers for continuous sync


## Structure
- `main.tf`: Root module, providers, and orchestration
- `variables.tf`: Input variables
- `demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `outputs.tf`: Outputs
- `modules/`
  - `resource_group/`: Resource group creation
  - `storage_account/`: Storage account and file share (SMB)
  - `storage_account_datalake/`: Data Lake Gen2 storage and filesystem
  - `data_factory/`: Data Factory, pipeline, and trigger automation (via ARM template)
- `../scripts/populate-source-fileshare.sh`: Populates the source file share with random files for demo/testing
- `../scripts/toggle-trigger.sh`: CLI tool to start/stop the Data Factory pipeline trigger



## Usage (Staged Apply for Data Factory Managed Identity)

**Step 1: Authenticate**

    az login

**Step 2: Edit Variables**

Edit only `demo.tfvars` to supply your Azure subscription, tenant, and resource names.

**Step 3: Initialize Terraform**

    terraform init

**Step 4: Create Data Factory and Managed Identity**

This step ensures the Data Factory principal is created and available for role assignments.

    terraform apply -target=module.data_factory_identity -var-file=demo.tfvars

**Step 5: Apply the Rest of the Infrastructure**

    terraform apply -var-file=demo.tfvars

This will:
  - Assign the required roles to the Data Factory managed identity
  - Create Data Factory managed private endpoints for source/destination Azure Files and Data Lake Gen2 endpoints
  - Deploy Data Factory pipelines, triggers, and linked services (including Data Lake Gen2)
  - Deploy all storage and supporting resources

**Step 6: (Optional) Populate Demo Data**

    ../scripts/populate-source-fileshare.sh
    ../scripts/populate-source-datalake.sh

**Step 7: (Optional) Control Data Factory Triggers**

    ../scripts/toggle-trigger.sh start|stop
    ../scripts/toggle-datalake-trigger.sh start|stop

**Notes:**
- Always run Step 4 first after a fresh deployment or destroy, so the principal_id is available for role assignments.
- If you change the Data Factory identity, repeat Step 4 and then Step 5.
- If you encounter ARM template errors, check for case-sensitive name mismatches and resource ordering in pipeline.json.
- Storage accounts and Data Factory have public network access disabled; Data Factory copy traffic is expected to flow through managed private endpoints in ADF managed VNet.
- Managed private endpoint connections can appear as pending in some subscriptions/tenants and may require approval on the target storage accounts.


## Automation & Patterns
- Storage account connection strings are automatically passed to Data Factory linked services—no manual secret handling required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All Data Factory objects (linked services, datasets, pipelines, triggers) are managed via ARM template for full automation and UI compatibility. **Resource ordering and case-sensitive naming are required for successful deployment.**
- Scripts are provided for demo data and trigger management


## Requirements
- Terraform >= 1.0
- Azure CLI authenticated

---


See `.github/copilot-instructions.md` for agent and contributor guidance.
