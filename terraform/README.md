# Azure Demo Environment with Terraform


# Azure Multi-Region File Sync Demo (Terraform)


# Azure Multi-Region File Sync Demo (Terraform)

This Terraform configuration deploys:
- Two resource groups (East US 2 and Canada East)
- Azure Storage Accounts with File Shares (Samba/SMB enabled)
- Azure Data Factory in Canada East to sync file shares between regions
- A scheduled Data Factory pipeline trigger for continuous sync

## Structure
- `main.tf`: Root module, providers, and orchestration
- `variables.tf`: Input variables
- `demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `outputs.tf`: Outputs
- `modules/`
  - `resource_group/`
  - `storage_account/`
  - `data_factory/` (includes ARM template for pipeline, datasets, linked services, and trigger)
- `../scripts/populate-source-fileshare.sh`: Populates the source file share with random files for demo/testing
- `../scripts/toggle-trigger.sh`: CLI tool to start/stop the Data Factory pipeline trigger

## Usage
1. Authenticate with Azure CLI: `az login`
2. Edit only `demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Run:
   - `terraform init`
   - `terraform plan -var-file=demo.tfvars`
   - `terraform apply -var-file=demo.tfvars`
4. (Optional) Run `../scripts/populate-source-fileshare.sh` to add demo files
5. (Optional) Use `../scripts/toggle-trigger.sh start|stop` to control the scheduled pipeline

## Automation & Patterns
- Storage account connection strings are automatically passed to Data Factory linked services—no manual secret handling required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All Data Factory objects (linked services, datasets, pipeline, trigger) are managed via ARM template for full automation and UI compatibility
- Scripts are provided for demo data and trigger management

## Requirements
- Terraform >= 1.0
- Azure CLI authenticated

---

See `.github/copilot-instructions.md` for agent and contributor guidance.
