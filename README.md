# Azure Datalake Object Replication with Azure Data Factory

This Terraform configuration deploys:
- Two resource groups (East US 2 and Canada East)
- Azure Storage Accounts with File Shares (Samba/SMB enabled) and Data Lake Gen2 in both regions
- Azure Data Factory in Canada East to sync file shares and Data Lake Gen2 between regions
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



## Usage (Phased Deployment)

**Step 1: Authenticate**

    az login

**Step 2: Edit Variables**

Edit only `demo.tfvars` to supply your Azure subscription, tenant, and resource names.

**Step 3: Initialize Terraform**

    terraform init

**Step 4: Phase 1 Gate - Resource Groups and Network Foundation**

Run this sequence to deploy the Phase 1 baseline in dependency order:

        terraform apply -target=module.eastus2_rg -target=module.canadaeast_rg -var-file=demo.tfvars
        terraform apply -target=module.eastus2_network -target=module.canadaeast_network -var-file=demo.tfvars

Validate Phase 1 before continuing:
    - Both VNets exist (East US 2 and Canada East)
    - Private endpoint subnet exists in each region
    - Private DNS zones are created and linked to each VNet
    - CIDR ranges do not overlap with your corporate networking

**Step 5: Continue with Existing Stack Deployment**

Continue with staged apply for Data Factory identity and full deployment:

        terraform apply -target=module.data_factory_identity -var-file=demo.tfvars
        terraform apply -var-file=demo.tfvars

**Step 6: (Optional) Populate Demo Data**

    ../scripts/populate-source-fileshare.sh
    ../scripts/populate-source-datalake.sh

**Step 7: (Optional) Control Data Factory Triggers**

    ../scripts/toggle-trigger.sh start|stop
    ../scripts/toggle-datalake-trigger.sh start|stop

**Step 8: (Optional) Automated Phase 1 Gate Test**

Run a single command that performs deploy, validation, and destroy for the
Phase 1 network foundation:

    ../scripts/test-phase1-network.sh

Useful options:
    ../scripts/test-phase1-network.sh --keep
    ../scripts/test-phase1-network.sh --destroy-only
    ../scripts/test-phase1-network.sh --destroy-rgs
    ../scripts/test-phase1-network.sh --tfvars demo.tfvars

**Notes:**
- Always run the Phase 1 gate before deploying private endpoint dependent services.
- Always run the Data Factory identity apply before full apply after a fresh deployment or destroy.
- If you change the Data Factory identity, repeat Step 5.
- The Phase 1 gate script destroys network resources by default; use `--keep` to preserve them for manual inspection.
- Use `--destroy-only` to tear down resources from a prior run that used `--keep`.
- Use `--destroy-rgs` only in disposable environments.
- If you encounter ARM template errors, check for case-sensitive name mismatches and resource ordering in pipeline.json.


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
