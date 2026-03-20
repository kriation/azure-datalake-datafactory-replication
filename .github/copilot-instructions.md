
# Copilot Instructions for AI Coding Agents



## Project Overview

This repository demonstrates a fully automated, multi-region Azure deployment using Terraform and ARM templates. It provisions:
- Resource groups in East US 2 and Canada East
- Regional VNets, private-endpoint subnets, and private DNS zones for private-link dependent services
- Regional Key Vaults with deny-by-default networking and private endpoints
- Customer-managed keys (CMKs) in regional Key Vaults for upcoming storage and Data Factory encryption work
- Azure Storage Accounts with File Shares (Samba/SMB enabled) and Data Lake Gen2 in both regions
- Azure Data Factory in Canada East to sync files and Data Lake Gen2 between regions
- Scheduled Data Factory pipeline triggers for continuous sync

## Architecture
- All infrastructure is defined in the `terraform/` directory using modules for resource groups, networking, Key Vault, CMKs, storage accounts (File Share and Data Lake Gen2), Data Factory identity, and Data Factory pipeline deployment.
- Data flow: Files placed in the East US 2 file share or Data Lake Gen2 are synced to the Canada East equivalents via automated Data Factory pipelines.
- The repository is being hardened in ordered phases. Current implemented phases are:
	- Phase 1: Resource groups, VNets, private-endpoint subnets, private DNS zones
	- Phase 2: Regional Key Vaults with private endpoints and deny-by-default network ACLs
	- Phase 3: Regional CMK creation and Key Vault RBAC for the deploying principal and Data Factory identity
	- Phase 4: Storage accounts with CMK binding, TLS1_2 policy validation, and disabled public network access
- All Data Factory objects (linked services, datasets, pipelines, triggers) are managed via a parameterized ARM template for full repeatability and UI compatibility. **Resource ordering and case-sensitive naming are critical for successful deployment.**
- Scripts in the `scripts/` directory support demo data population and trigger management.
- Terraform uses a single local state, but build-time validation uses staged `-target` applies in dependency order. Steady-state usage remains full `terraform plan` and `terraform apply`.

## Key Files & Structure
- `terraform/main.tf`: Root orchestration, providers, and module wiring
- `terraform/variables.tf`: Input variables (subscription, region, names)
- `terraform/demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `terraform/modules/`: Contains reusable modules:
	- `resource_group/`: Resource group creation
	- `network/`: VNet, private-endpoint subnet, private DNS zones, and VNet links
	- `key_vault/`: Regional Key Vault with private endpoint and deny-by-default networking
	- `encryption_keys/`: CMK creation in RBAC-enabled Key Vaults
	- `storage_account/`: Storage account and file share (SMB)
	- `data_factory/`: Data Factory, pipeline, and trigger automation (via ARM template)
	- `data_factory_identity/`: System-assigned Data Factory resource used to expose managed identity early in phased deployment
	- `storage_account_datalake/`: Data Lake Gen2 storage and filesystem
- `terraform/outputs.tf`: Exposes key resource names
- `README.md`: Phased deployment runbook, validation gates, and script usage
- `scripts/test-phase1-network.sh`: Self-contained Phase 1 integration test (deploy, validate, cleanup)
- `scripts/test-phase2-keyvault.sh`: Self-contained Phase 2 integration test with clearer timeout signaling for Key Vault destroy
- `scripts/test-phase3-cmk.sh`: Self-contained Phase 3 integration test for CMK creation and RBAC validation
- `scripts/test-phase4-storage-cmk-tls.sh`: Self-contained Phase 4 integration test for storage CMK bindings and TLS/public-access validation
- `scripts/populate-source-fileshare.sh`: Populates the source file share with random files for demo/testing
- `scripts/validate-adf-health.sh`: Minimal ADF replication health gate for trigger state and recent pipeline outcomes
- `scripts/toggle-trigger.sh`: CLI tool to start/stop the Data Factory pipeline trigger

## Developer Workflow
1. Authenticate with Azure CLI (`az login`)
2. Edit only `terraform/demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Use phased gates while building or validating new hardening layers:
	 - Phase 1: `terraform apply -target=module.eastus2_rg -target=module.canadaeast_rg -var-file=demo.tfvars`, then `terraform apply -target=module.eastus2_network -target=module.canadaeast_network -var-file=demo.tfvars`
	 - Phase 2: `terraform apply -target=module.eastus2_key_vault -target=module.canadaeast_key_vault -var-file=demo.tfvars`
	 - Phase 3: `terraform apply -target=module.data_factory_identity -target=module.eastus2_encryption_keys -target=module.canadaeast_encryption_keys -var-file=demo.tfvars`
	 - Phase 4: `terraform apply -target=module.eastus2_storage -target=module.canadaeast_storage -target=module.eastus2_datalake -target=module.canadaeast_datalake -target=azurerm_storage_account_customer_managed_key.eastus2_storage_cmk_binding -target=azurerm_storage_account_customer_managed_key.eastus2_datalake_cmk_binding -target=azurerm_storage_account_customer_managed_key.canadaeast_storage_cmk_binding -target=azurerm_storage_account_customer_managed_key.canadaeast_datalake_cmk_binding -var-file=demo.tfvars`
4. Prefer the self-contained phase gate scripts for validation:
	 - `scripts/test-phase1-network.sh`
	 - `scripts/test-phase2-keyvault.sh`
	 - `scripts/test-phase3-cmk.sh`
	 - `scripts/test-phase4-storage-cmk-tls.sh`
5. After phased validation, use full `terraform plan -var-file=demo.tfvars` and `terraform apply -var-file=demo.tfvars` only from an environment that can reach the private data plane. From a public workstation after Phase 4 lockdown, use `terraform plan -refresh=false -var-file=demo.tfvars` for convergence checks and the phase gate scripts for refreshed validation.
6. (Optional) Run `scripts/populate-source-fileshare.sh` or `scripts/populate-source-datalake.sh` to add demo data
7. (Optional) Use `scripts/toggle-trigger.sh start|stop` or `scripts/toggle-datalake-trigger.sh start|stop` to control the scheduled pipelines
8. (Recommended) Validate replication health with `scripts/validate-adf-health.sh` (or scope with `--pipelines copydatalakegen2pipeline` while fileshare private connectivity hardening is in progress)

## Conventions & Patterns
- All cross-module secrets (storage connection strings) are passed via module outputs and variables—no manual secret editing required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All Data Factory objects are managed via ARM template for full automation and UI compatibility. **Resource ordering and case-sensitive naming are required for successful deployment.**
- Phase test scripts must be self-contained: each later phase script bootstraps all prerequisite phases internally before validating its own phase.
- Phase test scripts use a standard cleanup interface:
	- `--cleanup-phase`: destroy only the current phase resources
	- `--cleanup-all`: destroy additional higher-phase resources when possible, but do not destroy Key Vaults or their prerequisite infrastructure once Phase 2 has been applied
- Key Vaults use RBAC authorization, so any phase that creates keys must explicitly grant the deploying principal sufficient Key Vault RBAC before creating CMKs.
- Phase 3 currently uses `hashicorp/time` waits to reduce Key Vault RBAC propagation flakiness before CMK creation.
- Because Key Vault key creation is a data-plane operation, the Phase 3 local test script temporarily enables public access for the caller's detected public IP, creates/validates CMKs, then restores Key Vault public access to disabled before the run completes.
- Phase 4 relies on Key Vault trusted service bypass (`AzureServices`) so storage accounts can perform CMK operations while Key Vault public network access remains disabled.
- Because Phase 4 requires purge-protected Key Vaults for storage CMK binding, phase test scripts no longer attempt to destroy Key Vaults once Phase 2 has been applied.
- Scripts are provided for demo data, trigger management, and per-phase validation

## Integration Points
- Azure CLI authentication required
- Azure RBAC propagation timing matters for Key Vault data-plane operations in RBAC-enabled vaults
- Local Terraform state may retain stale outputs after targeted destroys even when `terraform state list` is empty; treat `terraform state list` as the source of truth
- Data Factory pipelines and triggers are fully automated and repeatable

## Next Steps
- Update this file if you add new modules, workflows, or architectural changes
- Planned remaining phases after Phase 4:
	- Phase 5: Data Factory CMK enablement
	- Phase 6: Key Vault-backed linked service secret references
	- Phase 7: Operational script updates to use Key Vault-hosted secrets
	- Phase 8: Full-stack convergence and replication smoke tests
- If you encounter ARM template errors, check for case-sensitive name mismatches and resource ordering in pipeline.json.
- See `README.md` for phased deployment and validation details
