
# Copilot Instructions for AI Coding Agents



## Project Overview

This repository demonstrates a fully automated, multi-region Azure deployment using Terraform and ARM templates. It provisions:
- Resource groups in East US 2 and Canada East
- Azure Storage Accounts with File Shares (Samba/SMB enabled) and Data Lake Gen2 in both regions
- Azure Data Factory in Canada East to sync files and Data Lake Gen2 between regions
- Scheduled Data Factory pipeline triggers for continuous sync

## Architecture
- All infrastructure is defined in the `terraform/` directory using modules for resource groups, storage accounts (File Share and Data Lake Gen2), and Data Factory.
- Data flow: Files placed in the East US 2 file share or Data Lake Gen2 are synced to the Canada East equivalents via automated Data Factory pipelines.
- All Data Factory objects (linked services, datasets, pipelines, triggers) are managed via a parameterized ARM template for full repeatability and UI compatibility. **Resource ordering and case-sensitive naming are critical for successful deployment.**
- Scripts in the `scripts/` directory support demo data population and trigger management.

## Key Files & Structure
- `terraform/main.tf`: Root orchestration, providers, and module wiring
- `terraform/variables.tf`: Input variables (subscription, region, names)
- `terraform/demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `terraform/modules/`: Contains reusable modules:
	- `resource_group/`: Resource group creation
	- `storage_account/`: Storage account and file share (SMB)
	- `data_factory/`: Data Factory, pipeline, and trigger automation (via ARM template)
	- `storage_account_datalake/`: Data Lake Gen2 storage and filesystem
- `terraform/outputs.tf`: Exposes key resource names
- `terraform/README.md`: Usage and requirements
- `scripts/populate-source-fileshare.sh`: Populates the source file share with random files for demo/testing
- `scripts/toggle-trigger.sh`: CLI tool to start/stop the Data Factory pipeline trigger

## Developer Workflow
1. Authenticate with Azure CLI (`az login`)
2. Edit only `terraform/demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Run:
   - `terraform init`
   - `terraform apply -target=module.data_factory_identity -var-file=demo.tfvars` (creates Data Factory and managed identity)
   - `terraform apply -var-file=demo.tfvars` (deploys all resources, pipelines, triggers, and role assignments)
4. (Optional) Run `scripts/populate-source-fileshare.sh` to add demo files
5. (Optional) Use `scripts/toggle-trigger.sh start|stop` to control the scheduled pipeline

## Conventions & Patterns
- All cross-module secrets (storage connection strings) are passed via module outputs and variables—no manual secret editing required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All Data Factory objects are managed via ARM template for full automation and UI compatibility. **Resource ordering and case-sensitive naming are required for successful deployment.**
- Scripts are provided for demo data and trigger management

## Integration Points
- Azure CLI authentication required
- Data Factory pipelines and triggers are fully automated and repeatable

## Next Steps
- Update this file if you add new modules, workflows, or architectural changes
- If you encounter ARM template errors, check for case-sensitive name mismatches and resource ordering in pipeline.json.
- See `terraform/README.md` for usage details
