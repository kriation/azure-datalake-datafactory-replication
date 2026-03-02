
# Copilot Instructions for AI Coding Agents


## Project Overview
This repository demonstrates a multi-region Azure deployment using Terraform. It provisions:
- Resource groups in East US 2 and Canada East
- Azure Storage Accounts with File Shares (Samba/SMB enabled) in both regions
- Azure Data Factory in Canada East to sync files from East US 2 to Canada East

## Architecture
- All infrastructure is defined in the `terraform/` directory using modules for resource groups, storage accounts, and Data Factory.
- Data flow: Files placed in the East US 2 file share are synced to the Canada East file share via Azure Data Factory pipeline.
- Each region has its own resource group and storage account for isolation and clarity.
- Data Factory linked services are automatically configured using the storage account connection strings output from the modules—no manual secret handling required.

## Key Files & Structure
- `terraform/main.tf`: Root orchestration, providers, and module wiring
- `terraform/variables.tf`: Input variables (subscription, region, names)
- `terraform/demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `terraform/modules/`: Contains reusable modules:
	- `resource_group/`: Resource group creation
	- `storage_account/`: Storage account and file share (SMB)
	- `data_factory/`: Data Factory and pipeline wiring
- `terraform/outputs.tf`: Exposes key resource names
- `terraform/README.md`: Usage and requirements

## Developer Workflow
1. Authenticate with Azure CLI (`az login`)
2. Edit only `terraform/demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Run:
	 - `terraform init`
	 - `terraform plan -var-file=demo.tfvars`
	 - `terraform apply -var-file=demo.tfvars`
4. (Optional) Extend Data Factory pipeline logic in `modules/data_factory/main.tf`

## Conventions & Patterns
- All cross-module secrets (storage connection strings) are passed via module outputs and variables—no manual secret editing required
- Only `demo.tfvars` should be changed for new environments or redeployments
- Keep region-specific resources in separate modules for clarity
- Document any new modules or workflow changes in this file

## Integration Points
- Azure CLI authentication required
- Data Factory pipeline is a placeholder—customize for advanced sync scenarios

## Next Steps
- Update this file if you add new modules, workflows, or architectural changes
- See `terraform/README.md` for usage details
