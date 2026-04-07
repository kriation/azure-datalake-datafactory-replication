# Copilot Instructions for AI Coding Agents

## Project Summary

This repository deploys a secure, repeatable replication demo from East US 2 to Canada East.

Core behavior:
- Incremental copy every 5 minutes for Azure Files and ADLS Gen2
- Twice-daily delete reconciliation to keep destination mirrored
- Dedicated checkpoint storage for watermark state and logs

## Architecture at a Glance

- Terraform modules define all infrastructure and ADF artifacts.
- Data Factory uses Managed VNet IR and managed private endpoints.
- Key Vault uses RBAC and deny-by-default networking.
- Storage accounts use CMK, TLS1_2, and public network disabled.

Current phase status:
- Phase 1-8 implemented
- Phase 9 in progress: incremental + reconciliation hardening and operational validation

## Key Paths

- `terraform/main.tf`: root module wiring
- `terraform/variables.tf`: shared inputs
- `terraform/demo.tfvars`: environment values
- `terraform/modules/checkpoint_storage_account/`: checkpoint account and container
- `terraform/modules/data_factory/pipeline.json`: linked services, datasets, pipelines, triggers
- `scripts/execute-phase5-6.sh`: deploy ADF CMK + artifacts
- `scripts/approve-managed-private-endpoints.sh`: approve managed private endpoints
- `scripts/validate-adf-health.sh`: health checks for copy and reconciliation
- `scripts/toggle-trigger.sh`: fileshare copy trigger control
- `scripts/toggle-datalake-trigger.sh`: datalake copy trigger control
- `scripts/toggle-fileshare-reconcile-trigger.sh`: fileshare reconciliation trigger control
- `scripts/toggle-datalake-reconcile-trigger.sh`: datalake reconciliation trigger control
- `scripts/reset-to-keyvault-baseline.sh`: reset with checkpoint governance options

## Preferred Workflow

1. Authenticate: `az login`
2. Update only `terraform/demo.tfvars`
3. Run these scripts in order:
   - `scripts/test-phase4-storage-cmk-tls.sh --keep`
   - `scripts/execute-phase5-6.sh`
   - `scripts/approve-managed-private-endpoints.sh`
   - `scripts/populate-source-datalake.sh`
   - `scripts/populate-source-fileshare.sh`
   - `scripts/toggle-trigger.sh start`
   - `scripts/toggle-datalake-trigger.sh start`
   - `scripts/toggle-fileshare-reconcile-trigger.sh start`
   - `scripts/toggle-datalake-reconcile-trigger.sh start`
   - `scripts/validate-adf-health.sh`

## Implementation Rules

- Keep `README.md` and this file aligned in the same PR when workflow changes.
- Keep Data Factory artifact naming/order stable and case-consistent.
- Prefer script-first onboarding; do not replace with Terraform-only shortcuts.
- Add any new script to both `README.md` and this file.

## Operational Guardrails

- Reconciliation pipelines include a per-run delete cap to reduce blast radius.
- `validate-adf-health.sh` supports `--skip-reconcile-check` when reconcile triggers are paused.
- Reset script supports checkpoint audit preservation flags for demo vs strict operation.

## Troubleshooting Hints

- If ARM deploy fails, check case-sensitive names and resource ordering in `pipeline.json`.
- If replication fails after deployment, verify managed private endpoint approvals.
- For targeted destroy drift, trust `terraform state list` over stale outputs.
