# Azure Demo Environment with Terraform


# Azure Multi-Region File Sync Demo (Terraform)

This Terraform configuration deploys:
- Two resource groups (East US 2 and Canada East)
- Azure Storage Accounts with File Shares (Samba/SMB enabled)
- Azure Data Factory in Canada East to sync file shares between regions

## Structure
- `main.tf`: Root module, providers, and orchestration
- `variables.tf`: Input variables
- `demo.tfvars`: User-supplied values for repeatable, environment-specific deployments
- `outputs.tf`: Outputs
- `modules/`
  - `resource_group/`
  - `storage_account/`
  - `data_factory/`

## Usage
1. Authenticate with Azure CLI: `az login`
2. Edit only `demo.tfvars` to supply your Azure subscription, tenant, and resource names
3. Run:
   - `terraform init`
   - `terraform plan -var-file=demo.tfvars`
   - `terraform apply -var-file=demo.tfvars`

## Automation & Patterns
- Storage account connection strings are automatically passed to Data Factory linked services—no manual secret handling required
- Only `demo.tfvars` should be changed for new environments or redeployments
- All cross-module secrets are handled via module outputs and variables

## Requirements
- Terraform >= 1.0
- Azure CLI authenticated

---

See `.github/copilot-instructions.md` for agent and contributor guidance.
