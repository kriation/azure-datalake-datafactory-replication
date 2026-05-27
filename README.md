# Azure Files + ADLS Gen2 Replication Demo

This repo deploys a secure, script-driven demo that replicates data from East US 2 to Canada East.

What replicates:
- Azure Files (SMB)
- ADLS Gen2

How replication works:
- Copy pipelines run every 5 minutes using incremental watermark windows.
- Reconciliation pipelines run twice daily to delete destination-only items.
- Fileshare reconciliation walks nested folders via a bounded-depth pipeline chain
  (max depth 8) and enforces a global per-run delete cap tracked in a counter blob.
- A dedicated checkpoint storage account stores cursor state, the reconcile cap counter,
  and operational logs.

## What Gets Deployed

- Resource groups in East US 2 and Canada East
- VNets, private endpoint subnet, and private DNS zones
- Key Vault in each region with RBAC and private access
- CMKs for storage and Data Factory
- File share storage in both regions
- ADLS Gen2 storage in both regions
- Data Factory with managed VNet IR, linked services, datasets, pipelines, and triggers
- Checkpoint storage account and `adf-checkpoints` container

## Prerequisites

- Azure CLI authenticated (`az login`)
- Terraform installed
- Permissions for RG, network, Key Vault, RBAC, storage, and Data Factory

## Quick Start (Script-First)

1. Configure names and subscription values.

```bash
cd terraform
terraform init
# Edit demo.tfvars
```

2. Build storage/security baseline.

```bash
cd ../scripts
./test-phase4-storage-cmk-tls.sh --keep
```

3. Deploy Data Factory artifacts and secrets.

```bash
./execute-phase5-6.sh
```

This script also seeds missing checkpoint blobs for first-run safety.

4. Approve managed private endpoints.

```bash
./approve-managed-private-endpoints.sh
```

5. Add sample source data.

```bash
./populate-source-datalake.sh
./populate-source-fileshare.sh
```

6. Start all replication triggers.

```bash
./toggle-trigger.sh start
./toggle-datalake-trigger.sh start
./toggle-fileshare-reconcile-trigger.sh start
./toggle-datalake-reconcile-trigger.sh start
```

7. Validate health.

```bash
./validate-adf-health.sh
```

Healthy baseline:
- Triggers are `Started`
- Latest runs are `Succeeded` for:
  - `copyfilesharepipeline`
  - `copydatalakegen2pipeline`
  - `deletereconcilefilesharepipeline`
  - `deletereconciledalakepipeline`

## Day 2 Operations

Populate source:

```bash
./populate-source-datalake.sh
./populate-source-fileshare.sh
```

Control triggers:

```bash
./toggle-trigger.sh start
./toggle-trigger.sh stop
./toggle-datalake-trigger.sh start
./toggle-datalake-trigger.sh stop
./toggle-fileshare-reconcile-trigger.sh start
./toggle-fileshare-reconcile-trigger.sh stop
./toggle-datalake-reconcile-trigger.sh start
./toggle-datalake-reconcile-trigger.sh stop
```

Health checks:

```bash
./validate-adf-health.sh
./validate-adf-health.sh --skip-reconcile-check
```

## Reset to Baseline (Keep Resource Groups and Empty Key Vaults)

```bash
cd scripts
./reset-to-keyvault-baseline.sh
```

Useful options:

```bash
./reset-to-keyvault-baseline.sh --dry-run
./reset-to-keyvault-baseline.sh --no-auto-approve
./reset-to-keyvault-baseline.sh --preserve-checkpoint-audit
./reset-to-keyvault-baseline.sh --no-preserve-checkpoint-audit
./reset-to-keyvault-baseline.sh -f demo.tfvars
```

## Notes

- Keep `demo.tfvars` as the environment input file.
- ARM resource names/order are case-sensitive in the Data Factory template.
- Reconciliation includes a per-run delete cap for demo safety.
- Data Factory CMK binding is effectively permanent; removing it requires Data Factory recreation.

## Fileshare Reconciliation Design

The fileshare reconcile pipeline (`deletereconcilefilesharepipeline`) recursively
walks the destination share and deletes destination-only items, bounded by a
global per-run delete cap.

Pipeline shape:

- Entry pipeline `deletereconcilefilesharepipeline` initializes a counter blob
  in `stdcheckpointcanadaeast/adf-checkpoints/current/<adf_fileshare_reconcile_cap_blob_name>`
  (default `fileshare-reconcile-cap.json`) with the run id, cap, and `deleteCount=0`,
  then invokes `reconcilefilesharefolderlevel0`.
- Level pipelines `reconcilefilesharefolderlevel0..7` form a bounded-depth DAG.
  Each level runs `GetMetadata` on source and destination, then a sequential
  `ForEach` over destination children; per child it re-reads the cap counter,
  evaluates three parallel `IfCondition` branches (delete file, delete folder,
  recurse into subfolder), and increments the counter via Web Activity PUT after
  each delete. The recurse branch also gates on the cap so sibling subtrees are
  short-circuited once the cap is exhausted.
- ADF rejects self-referential `ExecutePipeline`, hence the bounded chain (max
  depth 8). Increase by raising `MAX_DEPTH` and regenerating the chain.

Operational behavior:

- Per-run cap is configurable via the pipeline parameter `deleteReconcileCapPerRun`
  (default from `adf_reconcile_delete_cap_per_run`). The trigger passes this in.
- Delete order is deepest-first (DFS); when the cap is hit, remaining files in
  the current level and all sibling subtrees are skipped.
- The counter blob is overwritten at the start of every run, so it always
  reflects the last completed/active run.

When developing or testing this pipeline manually, stop the scheduled trigger
first so a smoke run is not queued behind it:

```bash
./toggle-fileshare-reconcile-trigger.sh stop
# ...run smoke tests via az datafactory pipeline create-run ...
./toggle-fileshare-reconcile-trigger.sh start
```

## Repository Layout

- `terraform/`: root Terraform and variable files
- `terraform/modules/`: reusable modules (network, key vault, encryption keys, storage, datalake, checkpoint storage, data factory)
- `scripts/`: deployment, validation, trigger, and reset operations
- `.github/copilot-instructions.md`: contributor/agent implementation guidance
