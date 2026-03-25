
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
	- Phase 5: Data Factory CMK enablement
	- Phase 6: Key Vault-backed linked service secret references
	- Phase 7: Operational script updates to use Key Vault-hosted secrets (COMPLETE)
	- Phase 8: Managed Virtual Network integration runtime for secure fileshare replication (IN PROGRESS)
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
- `scripts/execute-phase5-6.sh`: Self-contained Phase 5/6 orchestration (ADF CMK, KV secrets, ARM deployment, and artifact validation/remediation)
- `scripts/approve-managed-private-endpoints.sh`: Approves managed private endpoint connections created by ADF managed VNet IR for fileshare routing
- `scripts/populate-source-fileshare.sh`: Populates the source file share with random files for demo/testing
- `scripts/populate-source-datalake.sh`: Populates the source Data Lake Gen2 filesystem with random files for demo/testing
- `scripts/toggle-datalake-trigger.sh`: CLI tool to start/stop the Data Lake Gen2 replication trigger
- `scripts/validate-adf-health.sh`: Minimal ADF replication health gate for trigger state and recent pipeline outcomes
- `scripts/toggle-trigger.sh`: CLI tool to start/stop the Data Factory pipeline trigger
- `scripts/reset-to-keyvault-baseline.sh`: Repeatable teardown to keep only demo resource groups and empty Key Vaults

## Developer Workflow
1. Authenticate with Azure CLI (`az login`)
2. Edit only `terraform/demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Preferred script-first deployment flow for a complete demo environment:
	 - `scripts/test-phase4-storage-cmk-tls.sh --keep`
	 - `scripts/execute-phase5-6.sh`
	 - `scripts/approve-managed-private-endpoints.sh`
	 - `scripts/populate-source-datalake.sh`
	 - `scripts/populate-source-fileshare.sh`
	 - `scripts/toggle-trigger.sh start`
	 - `scripts/toggle-datalake-trigger.sh start`
	 - `scripts/validate-adf-health.sh`
4. Use phased Terraform `-target` applies only for advanced/manual recovery or development of a specific hardening phase.
5. Prefer the self-contained phase gate scripts for validation:
	 - `scripts/test-phase1-network.sh`
	 - `scripts/test-phase2-keyvault.sh`
	 - `scripts/test-phase3-cmk.sh`
	 - `scripts/test-phase4-storage-cmk-tls.sh`
6. After phased validation, use full `terraform plan -var-file=demo.tfvars` and `terraform apply -var-file=demo.tfvars` only from an environment that can reach the private data plane. From a public workstation after Phase 4 lockdown, use `terraform plan -refresh=false -var-file=demo.tfvars` for convergence checks and the phase gate scripts for refreshed validation.
7. `scripts/approve-managed-private-endpoints.sh` is required after Phase 5/6 to enable fileshare replication over managed private endpoints.
8. Use `scripts/populate-source-fileshare.sh` and `scripts/populate-source-datalake.sh` to add demo data before starting triggers.
9. Use `scripts/toggle-trigger.sh start|stop` and `scripts/toggle-datalake-trigger.sh start|stop` to control scheduled pipelines.
10. Validate replication health with `scripts/validate-adf-health.sh` (or scope with `--pipelines copydatalakegen2pipeline` while fileshare private connectivity hardening is in progress).
11. (Reset for next test cycle) Run `scripts/reset-to-keyvault-baseline.sh` to keep only the two RGs and empty Key Vaults.

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
- File-share operational scripts now resolve connection strings from Key Vault-hosted secrets and restore network lockdown automatically after temporary bootstrap access.
- `scripts/execute-phase5-6.sh` includes ADF artifact assurance: if pipelines/triggers are missing after apply, it forces ARM deployment and re-validates.
- `scripts/validate-adf-health.sh` supports trigger name variants (lowercase template names and legacy cased names).
- `scripts/reset-to-keyvault-baseline.sh` requires sufficient RBAC (`Owner` or `Contributor` on both RGs and `Key Vault Administrator` on both vaults) to avoid partial teardown failures.
- Data Factory CMK enablement is modeled with `azurerm_data_factory_customer_managed_key`; once applied, Azure requires Data Factory recreation to remove the CMK binding.
- Azure also rejects adding a CMK to an existing Data Factory that already has entities deployed, so existing environments require a one-time Data Factory recreation; the Terraform graph should bind the CMK before the ARM template deploys ADF entities in fresh environments.

## Integration Points
- Azure CLI authentication required
- Azure RBAC propagation timing matters for Key Vault data-plane operations in RBAC-enabled vaults
- Local Terraform state may retain stale outputs after targeted destroys even when `terraform state list` is empty; treat `terraform state list` as the source of truth
- Data Factory pipelines and triggers are fully automated and repeatable

## Next Steps
- Update this file if you add new modules, workflows, or architectural changes


- Planned remaining phases after Phase 8:
	- Phase 9: End-to-end replication validation and operational runbooks
- Current Phase 8 status: Infrastructure deployed; managed private endpoint approval and replication validation are now part of the required operator workflow
- To complete Phase 8 in a deployment run: execute `scripts/approve-managed-private-endpoints.sh`, then start triggers and validate with `scripts/validate-adf-health.sh`
- If you encounter ARM template errors, check for case-sensitive name mismatches and resource ordering in pipeline.json.
- See `README.md` for phased deployment and validation details

## Contributor Guardrails
- Keep `README.md` as the source of truth for operator workflow order. If workflow steps change, update `README.md` and this file in the same pull request.
- Any new or renamed script in `scripts/` must be added to both `README.md` and the **Key Files & Structure** section here.
- Preserve script-first onboarding for new contributors; avoid introducing Terraform-only quick paths that bypass required operational scripts.
- Keep Data Factory artifact naming and ordering case-consistent in `terraform/modules/data_factory/pipeline.json` to avoid ARM deployment drift.
