
# Copilot Instructions for AI Coding Agents



## Project Overview
This repository demonstrates a fully automated, multi-region Azure deployment using Terraform and ARM templates. It provisions:
- Resource groups in East US 2 and Canada East
- Azure Storage Accounts with File Shares (Samba/SMB enabled) in both regions
- Azure Data Factory in Canada East to sync files from East US 2 to Canada East
- A scheduled Data Factory pipeline trigger for continuous sync

## Architecture
- All infrastructure is defined in the `terraform/` directory using modules for resource groups, storage accounts, and Data Factory.
- Data flow: Files placed in the East US 2 file share are synced to the Canada East file share via an automated Data Factory pipeline.
- All Data Factory objects (linked services, datasets, pipeline, trigger) are managed via a parameterized ARM template for full repeatability and UI compatibility.
- Scripts in the `scripts/` directory support demo data population and trigger management.

## Key Files & Structure
- `terraform/main.tf`: Root orchestration, providers, and module wiring
- `terraform/variables.tf`: Input variables (subscription, region, names)
- `terraform/demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `terraform/modules/`: Contains reusable modules:
	- `resource_group/`: Resource group creation
	- `storage_account/`: Storage account and file share (SMB)
	- `data_factory/`: Data Factory, pipeline, and trigger automation
- `terraform/outputs.tf`: Exposes key resource names
- `terraform/README.md`: Usage and requirements
- `scripts/populate-source-fileshare.sh`: Populates the source file share with random files for demo/testing
- `scripts/toggle-trigger.sh`: CLI tool to start/stop the Data Factory pipeline trigger

## Developer Workflow
1. Authenticate with Azure CLI (`az login`)
2. Edit only `terraform/demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Run:
	 - `terraform init`
	 - `terraform plan -var-file=demo.tfvars`
	 - `terraform apply -var-file=demo.tfvars`
4. (Optional) Run `scripts/populate-source-fileshare.sh` to add demo files
5. (Optional) Use `scripts/toggle-trigger.sh start|stop` to control the scheduled pipeline

## Conventions & Patterns
- All cross-module secrets (storage connection strings) are passed via module outputs and variables—no manual secret editing required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All Data Factory objects are managed via ARM template for full automation and UI compatibility
- Scripts are provided for demo data and trigger management

## Integration Points
- Azure CLI authentication required
- Data Factory pipeline and trigger are fully automated and repeatable

## Next Steps
- Update this file if you add new modules, workflows, or architectural changes
- See `terraform/README.md` for usage details
