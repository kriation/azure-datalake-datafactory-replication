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
- `../scripts/validate-adf-health.sh`: Minimal replication health gate based on trigger state and recent pipeline run outcomes



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

Before continuing with storage CMK work, run the Phase 3 gate:

    terraform apply -target=module.data_factory_identity -target=module.eastus2_encryption_keys -target=module.canadaeast_encryption_keys -var-file=demo.tfvars

Validate Phase 3 before continuing:
    - CMK keys exist in both regional Key Vaults
    - The deploying principal has Key Vault Administrator RBAC on both vaults
    - The Canada East Data Factory identity has Key Vault Crypto Service Encryption User RBAC
    - Key Vaults are restored to `publicNetworkAccess = Disabled` after the local CMK bootstrap completes

Before continuing with Data Factory CMK hardening, run the Phase 4 gate:

    terraform apply -target=module.eastus2_storage -target=module.canadaeast_storage -target=module.eastus2_datalake -target=module.canadaeast_datalake -target=azurerm_storage_account_customer_managed_key.eastus2_storage_cmk_binding -target=azurerm_storage_account_customer_managed_key.eastus2_datalake_cmk_binding -target=azurerm_storage_account_customer_managed_key.canadaeast_storage_cmk_binding -target=azurerm_storage_account_customer_managed_key.canadaeast_datalake_cmk_binding -var-file=demo.tfvars

Validate Phase 4 before continuing:
    - Storage key source is `Microsoft.Keyvault` for all file share and Data Lake storage accounts
    - Minimum TLS version is `TLS1_2` for all storage accounts
    - Public network access is disabled for all storage accounts

Before continuing with Key Vault-backed linked service secret references, run the Phase 5 gate:

    terraform apply -target=azurerm_data_factory_customer_managed_key.canadaeast_data_factory_cmk_binding -var-file=demo.tfvars

Validate Phase 5 before continuing:
    - Data Factory is bound to the Canada East CMK (`canadaeast_data_factory_cmk_key_id`)
    - The Data Factory CMK binding resource exists in state/output (`canadaeast_data_factory_cmk_binding_id`)
    - The Canada East Data Factory identity retains Key Vault Crypto Service Encryption User RBAC on the Canada East vault
    - Note: Data Factory CMK binding is effectively permanent; removing it requires recreating the factory
    - Existing factories that already contain linked services, datasets, pipelines, or triggers must be recreated once before this phase can succeed; Azure rejects adding CMK to a populated factory

Before continuing with operational script secret consumption, run the Phase 6 gate:

    terraform apply -target=azurerm_key_vault_secret.adf_source_fileshare_connection_string -target=azurerm_key_vault_secret.adf_dest_fileshare_connection_string -target=module.data_factory -var-file=demo.tfvars

Validate Phase 6 before continuing:
    - ADF linked service `adf-keyvault` exists and points to the Canada East Key Vault URI
    - ADF file share linked services reference Key Vault secrets (not inline connection strings)
    - Key Vault secrets exist for source and destination file share connection strings
    - The Data Factory identity has Key Vault Secrets User RBAC on the Canada East vault

**Step 6: (Optional) Populate Demo Data**

    ../scripts/populate-source-fileshare.sh
    ../scripts/populate-source-datalake.sh

The file-share populate script now reads its connection string from the
Canada East Key Vault secret (`adf-source-fileshare-connection-string`) and
temporarily opens both Key Vault and source storage network access from the
current operator IP before restoring lockdown.

**Step 7: (Optional) Control Data Factory Triggers**

    ../scripts/toggle-trigger.sh start|stop
    ../scripts/toggle-datalake-trigger.sh start|stop

**Step 7b: Recommended Replication Health Validation**

Use a minimal health gate that validates trigger runtime state and the latest
pipeline run outcomes in a recent lookback window:

    ../scripts/validate-adf-health.sh

Useful options:
    ../scripts/validate-adf-health.sh --hours 12
    ../scripts/validate-adf-health.sh --pipelines copydatalakegen2pipeline
    ../scripts/validate-adf-health.sh --skip-trigger-check

**Step 7c: Phase 7 Gate - Operational Script Secret Consumption**

Validate Phase 7 before continuing:
    - `../scripts/populate-source-fileshare.sh` reads source connection string from Key Vault (not storage key list)
    - The script restores Key Vault and storage public network access to `Disabled` at exit
    - Script arguments support overriding the Key Vault name and secret name for environment portability

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

Run a single command that performs deploy and validation for the
Phase 2 Key Vault foundation:

    ../scripts/test-phase2-keyvault.sh

Useful options:
    ../scripts/test-phase2-keyvault.sh --keep
    ../scripts/test-phase2-keyvault.sh --cleanup-phase
    ../scripts/test-phase2-keyvault.sh --cleanup-all
    ../scripts/test-phase2-keyvault.sh --tfvars demo.tfvars

**Step 10: (Optional) Automated Phase 3 Gate Test**

Run a single command that performs deploy, validation, and targeted cleanup for the
Phase 3 CMK and Key Vault RBAC foundation:

    ../scripts/test-phase3-cmk.sh

Useful options:
    ../scripts/test-phase3-cmk.sh --keep
    ../scripts/test-phase3-cmk.sh --cleanup-phase
    ../scripts/test-phase3-cmk.sh --cleanup-all
    ../scripts/test-phase3-cmk.sh --tfvars demo.tfvars

**Step 11: (Optional) Automated Phase 4 Gate Test**

Run a single command that performs deploy, validation, and targeted cleanup for the
Phase 4 storage CMK and TLS hardening foundation:

    ../scripts/test-phase4-storage-cmk-tls.sh

Useful options:
    ../scripts/test-phase4-storage-cmk-tls.sh --keep
    ../scripts/test-phase4-storage-cmk-tls.sh --cleanup-phase
    ../scripts/test-phase4-storage-cmk-tls.sh --cleanup-all
    ../scripts/test-phase4-storage-cmk-tls.sh --tfvars demo.tfvars

**Phase Test Script Dependency Model**

Each phase test script is **self-contained and can run independently**:

- `test-phase1-network.sh`: Deploys Phase 1 (RGs + network), validates, and destroys
- `test-phase2-keyvault.sh`: Internally deploys Phase 1 prerequisites (RGs + network), then deploys Phase 2 (Key Vault), validates both, and retains Key Vaults plus their prerequisite infrastructure
- `test-phase3-cmk.sh`: Internally deploys Phases 1-2 plus Data Factory identity, then deploys Phase 3 CMKs and RBAC, validates, and destroys only Phase 3 resources
- `test-phase4-storage-cmk-tls.sh`: Internally deploys Phases 1-3, then deploys Phase 4 storage CMK + TLS controls, validates, and destroys Phase 4 resources (optionally also Phase 3 resources with `--cleanup-all`)
- **Phase 4+ scripts will follow the same pattern**: Each phase test script will internally bootstrap all prior-phase prerequisites

This design enables:
- **Independent testing**: Run `test-phase2-keyvault.sh` without ever running `test-phase1-network.sh`
- **Lifecycle control**: From Phase 2 onward, Key Vaults and their prerequisite infrastructure are retained; cleanup flags remove only higher-phase resources
- **Rapid iteration**: Test individual phases in isolation during development

The phased Terraform apply sequence (Steps 4-5) follows the same dependency model manually for CI/CD pipelines and production deployments.

**Phase Test Script Cleanup Flags**

- `--cleanup-phase`: Destroy only the current phase's resources (skip deploy/validate)
- `--cleanup-all`: For Phase 1, destroy current phase and resource groups. For Phase 3-4, remove higher-phase resources while retaining Key Vault infrastructure; implies `--cleanup-phase`

**Notes:**
- Always run the Phase 1 gate (`terraform apply -target=module.eastus2_rg -target=module.canadaeast_rg -target=module.eastus2_network -target=module.canadaeast_network`) before deploying private endpoint–dependent services (such as Key Vault).
- Alternatively, use `test-phase2-keyvault.sh` which internally deploys Phase 1 prerequisites and is self-contained.
- Always run the Data Factory identity apply before full apply after a fresh deployment or destroy.
- If you change the Data Factory identity, repeat Step 5.
- The Phase 1 gate script destroys network resources by default; use `--keep` to preserve them for manual inspection.
- Use `--cleanup-phase` to destroy only phase-specific resources from a prior run that used `--keep`.
- Use `--cleanup-all` on Phase 1 only in disposable environments (removes RGs).
- The Phase 2 gate script (`test-phase2-keyvault.sh`) retains Key Vaults, networks, and resource groups after validation because purge-protected Key Vaults are not destroyed by the test harness.
- The Phase 3 gate script (`test-phase3-cmk.sh`) destroys CMKs, their Key Vault RBAC assignments, and the Data Factory identity by default; `--cleanup-all` does not remove Key Vaults or lower-phase prerequisites.
- The Phase 3 gate script (`test-phase3-cmk.sh`) temporarily allows the caller's current public IP to reach the Key Vault data plane so local Terraform can create CMKs, then restores both vaults to `publicNetworkAccess = Disabled` before completion.
- The Phase 4 gate script (`test-phase4-storage-cmk-tls.sh`) destroys storage CMK bindings, storage Key Vault RBAC assignments, and storage modules by default; `--cleanup-all` additionally removes Phase 3 CMKs and related RBAC, but retains Key Vaults and lower-phase prerequisites.
- Phase 5 uses `azurerm_data_factory_customer_managed_key` to bind the Canada East Data Factory to a Canada East Key Vault key; Azure does not support removing this binding in place, so rollback requires recreating the Data Factory.
- For fresh environments, the Terraform graph now binds the Data Factory CMK before deploying ARM-managed ADF entities. For existing environments that already deployed ADF entities without CMK, perform a one-time Data Factory recreation before applying Phase 5.
- Phase 6 stores file share connection strings in Canada East Key Vault secrets and updates ADF linked services to resolve those secrets through an ADF Key Vault linked service.
- Storage CMK operations rely on trusted Azure service access to Key Vault (`key_vault_bypass = "AzureServices"` in `demo.tfvars`).
- From Phase 4 onward, `key_vault_purge_protection_enabled = true` is required for storage CMK binding, which makes Key Vault teardown a non-goal for the phase test scripts.
- After Phase 4 lockdown is restored, a plain `terraform plan -var-file=demo.tfvars` from a public workstation can fail while refreshing Key Vault keys and Data Lake filesystems. Those are data-plane resources and require either private-network reachability or a temporary bootstrap exception.
- From outside the private network boundary, use `terraform plan -refresh=false -var-file=demo.tfvars` for config-versus-state convergence checks. Use the phase gate scripts for refreshed validation of locked-down phases.
- Azure does not allow fully disabling Key Vault soft delete.
- If you encounter ARM template errors, check for case-sensitive name mismatches and resource ordering in pipeline.json.


## Automation & Patterns
- Storage account connection strings are automatically passed to Data Factory linked services—no manual secret handling required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All Data Factory objects (linked services, datasets, pipelines, triggers) are managed via ARM template for full automation and UI compatibility. **Resource ordering and case-sensitive naming are required for successful deployment.**
- Scripts are provided for demo data and trigger management
- Replication validation is standardized on `scripts/validate-adf-health.sh` for post-Phase-4 locked-down environments.


## Requirements
- Terraform >= 1.0
- Azure CLI authenticated

---


See `.github/copilot-instructions.md` for agent and contributor guidance.
