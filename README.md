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

- Driver pipeline `deletereconcilefilesharepipeline` initializes the cap counter
  blob `stdcheckpointcanadaeast/adf-checkpoints/current/<adf_fileshare_reconcile_cap_blob_name>`
  (default `fileshare-reconcile-cap.json`) with the run id, cap, and `deleteCount=0`,
  seeds an empty current-frontier block blob and an empty next-frontier append
  blob, writes the root folder into next-frontier, then enters an `Until` loop.
  Each iteration: promote next-frontier → current-frontier, reset next-frontier,
  invoke `reconcilefilesharefrontierbatch`, re-read cap counter and next-frontier
  for the termination predicate.
- Batch pipeline `reconcilefilesharefrontierbatch` reads current-frontier and
  runs a sequential `ForEach`, invoking `reconcilefilesharefolderworker` per
  folder.
- Worker pipeline `reconcilefilesharefolderworker` runs `GetMetadata` on source
  and destination for a single folder, iterates destination children, re-reads
  the cap counter before each potential delete, and (a) deletes orphan files
  via `MaybeDeleteFile`, (b) deletes orphan folders wholesale via
  `MaybeDeleteFolder` (single recursive `Delete`, counted as one cap unit), or
  (c) appends the subfolder to next-frontier via `MaybeEnqueueSubfolder` so the
  next BFS level descends into it. Each delete increments the cap counter via
  Web Activity PUT.
- Frontier state lives in two checkpoint blobs:
  - `<adf_fileshare_reconcile_current_frontier_blob_name>` (default
    `fileshare-reconcile-current-frontier.json`) — block blob, JSON array.
  - `<adf_fileshare_reconcile_next_frontier_blob_name>` (default
    `fileshare-reconcile-next-frontier.json`) — append blob, NDJSON. Workers
    append concurrently via `PUT ?comp=appendblock`; no read-modify-write.
- ADF rejects self-referential `ExecutePipeline`, `IfCondition` containing
  loops, and `Until` directly containing `ForEach`. The driver/batch/worker
  split exists to satisfy all three constraints.

Operational behavior:

- Per-run cap is configurable via the pipeline parameter `deleteReconcileCapPerRun`
  (default from `adf_reconcile_delete_cap_per_run`). The trigger passes this in.
- Delete order is BFS (level-by-level, then alphabetical within a level). When
  the cap is hit, the worker stops issuing deletes and the driver's termination
  predicate ends the `Until` loop before the next level runs.
- The counter and frontier blobs are overwritten at the start of every run, so
  they always reflect the last completed/active run.

Depth limit (configurable):

- BFS depth is bounded by `adf_fileshare_reconcile_max_depth` (default `32`).
  At max depth, `MaybeEnqueueSubfolder` stops enqueuing children and the parent
  `MaybeDeleteFolder` deletes the subtree wholesale as one cap unit. To raise
  the limit, bump the variable and redeploy via `scripts/execute-phase5-6.sh`.
  No pipeline regeneration required.

When developing or testing this pipeline manually, stop the scheduled trigger
first so a smoke run is not queued behind it:

```bash
./toggle-fileshare-reconcile-trigger.sh stop
# ...run smoke tests via az datafactory pipeline create-run ...
./toggle-fileshare-reconcile-trigger.sh start
```

## Datalake Reconciliation Design

The Data Lake Gen2 reconcile pipeline (`deletereconciledalakepipeline`) mirrors
the fileshare BFS design exactly: a driver pipeline initializes the per-run cap
counter and frontier blobs, then drives a level-by-level BFS via a batch
pipeline and per-folder workers.

Pipeline shape:

- Driver pipeline `deletereconciledalakepipeline` initializes the cap counter
  blob `stdcheckpointcanadaeast/adf-checkpoints/current/<adf_datalake_reconcile_cap_blob_name>`
  (default `datalake-reconcile-cap.json`), seeds an empty current-frontier
  block blob and an empty next-frontier append blob, writes the root folder
  (defaulting to the destination filesystem name) into next-frontier, then
  enters an `Until` loop. Each iteration: promote next-frontier →
  current-frontier, reset next-frontier, invoke
  `reconciledatalakefrontierbatch`, re-read cap counter and next-frontier for
  the termination predicate.
- Batch pipeline `reconciledatalakefrontierbatch` reads current-frontier and
  runs a sequential `ForEach`, invoking `reconciledatalakefolderworker` per
  folder.
- Worker pipeline `reconciledatalakefolderworker` runs `GetMetadata` on source
  and destination for a single folder, iterates destination children, re-reads
  the cap counter before each potential delete, and (a) deletes orphan files
  via `MaybeDeleteFile`, (b) deletes orphan folders wholesale via
  `MaybeDeleteFolder` (single recursive `Delete` with
  `AzureBlobFSReadSettings`, counted as one cap unit), or (c) appends the
  subfolder to next-frontier via `MaybeEnqueueSubfolder` so the next BFS level
  descends into it. Each delete increments the cap counter via Web Activity PUT.
- Frontier state lives in two checkpoint blobs:
  - `<adf_datalake_reconcile_current_frontier_blob_name>` (default
    `datalake-reconcile-current-frontier.json`) — block blob, JSON array.
  - `<adf_datalake_reconcile_next_frontier_blob_name>` (default
    `datalake-reconcile-next-frontier.json`) — append blob, NDJSON. Workers
    append concurrently via `PUT ?comp=appendblock`; no read-modify-write.
- Folder paths are composed as `concat(folderPath, '/', item().name)` because
  the ADLS Gen2 root is the filesystem name (no leading-slash edge case,
  unlike the fileshare chain).
- The same ADF constraints apply (no self-referential `ExecutePipeline`, no
  `IfCondition` containing loops, no `Until` directly containing `ForEach`);
  the driver/batch/worker split exists to satisfy all three.

Depth limit (configurable):

- BFS depth is bounded by `adf_datalake_reconcile_max_depth` (default `32`).
  At max depth, `MaybeEnqueueSubfolder` stops enqueuing children and the parent
  `MaybeDeleteFolder` deletes the subtree wholesale as one cap unit. To raise
  the limit, bump the variable and redeploy via `scripts/execute-phase5-6.sh`.
  No pipeline regeneration required.

When developing or testing this pipeline manually, stop the scheduled trigger
first so a smoke run is not queued behind it:

```bash
./toggle-datalake-reconcile-trigger.sh stop
# ...run smoke tests via az datafactory pipeline create-run ...
./toggle-datalake-reconcile-trigger.sh start
```

## Repository Layout

- `terraform/`: root Terraform and variable files
- `terraform/modules/`: reusable modules (network, key vault, encryption keys, storage, datalake, checkpoint storage, data factory)
- `scripts/`: deployment, validation, trigger, and reset operations
- `.github/copilot-instructions.md`: contributor/agent implementation guidance
