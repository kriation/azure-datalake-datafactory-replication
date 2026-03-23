# Azure Files + ADLS Gen2 Replication Framework

This repository is a practical framework for deploying secure replication between two non-paired Azure regions for business continuity.

Replication scope:
- Azure Files (SMB)
- Azure Data Lake Storage Gen2 (ADLSv2)

Control plane:
- Azure Data Factory in Canada East

Security model:
- Private networking (VNets, PE subnets, private DNS)
- Regional Key Vaults with deny-by-default access
- Customer-managed keys (CMK) for storage and Data Factory
- Storage hardened to TLS1_2 and no public network access

## What This Deploys

- East US 2 and Canada East resource groups
- Regional network foundations for private-link dependent services
- Regional Key Vaults and CMK keys
- Azure Files + ADLS Gen2 in both regions
- Data Factory pipelines/triggers/linked services via ARM template
- Key Vault secret-backed linked service connection strings

## Prerequisites

- Azure CLI authenticated (`az login`)
- Terraform installed
- Sufficient Azure permissions for networking, RBAC, Key Vault, storage, and Data Factory

## Script Purpose Guide

- `test-phase1-network.sh`: builds and validates base networking (resource groups, VNets, private endpoint subnet, private DNS).
- `test-phase2-keyvault.sh`: builds and validates regional Key Vaults with private access controls.
- `test-phase3-cmk.sh`: builds and validates CMKs and required Key Vault RBAC.
- `test-phase4-storage-cmk-tls.sh`: deployment gate that bootstraps phases 1-3, deploys storage and ADLS Gen2, applies storage CMK bindings, enforces TLS/public access policy, and validates the result.
- `execute-phase5-6.sh`: required Phase 5-6 gate that applies ADF CMK + Key Vault secrets and deploys Data Factory artifacts (linked services, datasets, pipelines, triggers).
- `validate-adf-health.sh`: runtime health check for ADF triggers and latest pipeline outcomes.

## Required Path For A Working Demo

1. Configure environment values.

```bash
cd terraform
terraform init
# edit demo.tfvars for your subscription/tenant/resource names
```

2. Run the required storage/security gate.

```bash
cd ../scripts
./test-phase4-storage-cmk-tls.sh --keep
```

This script invokes prerequisite phases internally and completes the storage/security baseline.

3. Run the required Phase 5-6 gate.

```bash
./execute-phase5-6.sh
```

This step is mandatory for a working demonstration because it deploys the Data Factory replication artifacts.

4. Validate environment health.

```bash
./validate-adf-health.sh
```

Expected healthy output includes all of the following:
- Trigger states = `Started`
- Latest run status = `Succeeded` for `copyfilesharepipeline` and `copydatalakegen2pipeline`

5. Generate demo data and let replication run.

```bash
./populate-source-fileshare.sh
./populate-source-datalake.sh
```

6. Confirm trigger state (if needed) and re-check health.

```bash
./toggle-trigger.sh start
./toggle-datalake-trigger.sh start
./validate-adf-health.sh
```

When these checks pass, the environment is fully stood up and ready for demonstration.

## Daily Operations (After Initial Stand-Up)

- Populate source data:

```bash
./populate-source-fileshare.sh
./populate-source-datalake.sh
```

- Trigger control:

```bash
./toggle-trigger.sh start
./toggle-trigger.sh stop
./toggle-datalake-trigger.sh start
./toggle-datalake-trigger.sh stop
```

- Health check:

```bash
./validate-adf-health.sh
```

## Reset For Next-Day Demo (Keep Only RG + Empty Key Vaults)

Use this when you want to purge the environment and keep only the two resource groups and two empty Key Vaults.

Required permissions for the current operator:
- `Owner` or `Contributor` on both demo resource groups.
- `Key Vault Administrator` on both regional Key Vaults.

```bash
cd scripts
./reset-to-keyvault-baseline.sh
```

Behavior:
- Retains: resource groups and regional Key Vaults.
- Removes: Phase 3 CMKs/RBAC identity resources, Phase 4 storage+datalake+CMK bindings, Phase 5/6 ADF resources and ADF Key Vault secrets, and Phase 1 network/private DNS resources.

Optional flags:

```bash
./reset-to-keyvault-baseline.sh --dry-run
./reset-to-keyvault-baseline.sh --no-auto-approve
./reset-to-keyvault-baseline.sh -f demo.tfvars
```

## Optional: Managed Private Endpoint Approval Helper

If your environment requires manual managed private endpoint approvals for file-share routing through managed VNet IR:

```bash
./approve-managed-private-endpoints.sh
```

## Notes

- In locked-down/public-workstation contexts, run the repository scripts instead of direct Terraform plan/apply commands:

```bash
cd ../scripts
./test-phase4-storage-cmk-tls.sh
./execute-phase5-6.sh
./validate-adf-health.sh
```

- `execute-phase5-6.sh` is required for full deployment completion because it deploys the Data Factory ARM artifacts used for replication.

- Data Factory CMK binding is effectively permanent; removing it requires Data Factory recreation.
- ADF ARM template names and resource order are case-sensitive.

## Repository Structure

- `terraform/`: Root Terraform configuration and modules
- `terraform/modules/`: Network, Key Vault, encryption keys, storage, datalake, Data Factory modules
- `scripts/`: Phase deployment/validation scripts and operational helpers

For contributor/agent guidance, see `.github/copilot-instructions.md`.
