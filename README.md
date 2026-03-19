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

Before continuing with full stack deployment, run the Phase 2 gate:

        terraform apply -target=module.eastus2_key_vault -target=module.canadaeast_key_vault -var-file=demo.tfvars

Validate Phase 2 before continuing:
    - Key Vault public network access is disabled in both regions
    - Key Vault private endpoints are provisioned and approved
    - Key Vault private DNS zone group binding is present

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
    ../scripts/test-phase1-network.sh --cleanup-phase
    ../scripts/test-phase1-network.sh --cleanup-all
    ../scripts/test-phase1-network.sh --tfvars demo.tfvars

**Step 9: (Optional) Automated Phase 2 Gate Test**

Run a single command that performs deploy, validation, and destroy for the
Phase 2 Key Vault foundation:

    ../scripts/test-phase2-keyvault.sh

Useful options:
    ../scripts/test-phase2-keyvault.sh --keep
    ../scripts/test-phase2-keyvault.sh --cleanup-phase
    ../scripts/test-phase2-keyvault.sh --cleanup-all
    ../scripts/test-phase2-keyvault.sh --tfvars demo.tfvars

**Phase Test Script Dependency Model**

Each phase test script is **self-contained and can run independently**:

- `test-phase1-network.sh`: Deploys Phase 1 (RGs + network), validates, and destroys
- `test-phase2-keyvault.sh`: Internally deploys Phase 1 prerequisites (RGs + network), then deploys Phase 2 (Key Vault), validates both, and destroys Phase 2 (optionally Phase 1 with `--cleanup-all`)
- **Phase 3+ scripts will follow the same pattern**: Each phase test script will internally bootstrap all prior-phase prerequisites

This design enables:
- **Independent testing**: Run `test-phase2-keyvault.sh` without ever running `test-phase1-network.sh`
- **Lifecycle control**: Use `--cleanup-all` to clean up all phases, or omit it to preserve earlier phases for inspection
- **Rapid iteration**: Test individual phases in isolation during development

The phased Terraform apply sequence (Steps 4-5) follows the same dependency model manually for CI/CD pipelines and production deployments.

**Phase Test Script Cleanup Flags**

- `--cleanup-phase`: Destroy only the current phase's resources (skip deploy/validate)
- `--cleanup-all`: Destroy current phase AND all prerequisites; implies `--cleanup-phase` (no re-deploy)

**Notes:**
- Always run the Phase 1 gate (`terraform apply -target=module.eastus2_rg -target=module.canadaeast_rg -target=module.eastus2_network -target=module.canadaeast_network`) before deploying private endpoint–dependent services (such as Key Vault).
- Alternatively, use `test-phase2-keyvault.sh` which internally deploys Phase 1 prerequisites and is self-contained.
- Always run the Data Factory identity apply before full apply after a fresh deployment or destroy.
- If you change the Data Factory identity, repeat Step 5.
- The Phase 1 gate script destroys network resources by default; use `--keep` to preserve them for manual inspection.
- Use `--cleanup-phase` to destroy only phase-specific resources from a prior run that used `--keep`.
- Use `--cleanup-all` on Phase 1 only in disposable environments (removes RGs).
- The Phase 2 gate script (`test-phase2-keyvault.sh`) destroys only Key Vault resources by default; use `--cleanup-all` to also remove Phase 1 prerequisites (network + RGs).
- Key Vault delete is asynchronous in Azure; the script will emit a clear status message if Terraform times out and the vault is already removed from active resources.
- If re-deploying fails due to a soft-deleted vault holding the name, the script will print an exact remediation command to purge it manually.
- For demonstration speed, purge protection is disabled and Key Vault soft-delete retention is set to 7 days.
- Azure does not allow fully disabling Key Vault soft delete.
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
