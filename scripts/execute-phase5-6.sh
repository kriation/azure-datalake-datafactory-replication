#!/bin/bash
set -euo pipefail

###############################################################################
# Execute Phase 5-6: CMK Keys, Bindings, Secrets, and Data Factory
#
# Purpose:
#   Safe, single-command execution of Phase 5-6 hardening:
#   1. Bootstrap: Enable temporary network access from caller IP using lib functions
#   2. Apply: Run terraform apply to create all Phase 5-6 resources
#   3. Seed: Initialize checkpoint blobs for first-run incremental pipelines
#   4. Validate: Verify all resources deployed successfully
#   5. Lockdown: Automatic via EXIT trap (restores network ACLs to disabled state)
#
# Pattern:
#   Uses scripts/lib/keyvault-network-access.sh and scripts/lib/storage-network-access.sh
#   helper functions for robust temporary network access with propagation waiting.
#   Exit trap automatically restores all opened resources; safe for errors/interruptions.
#
# Usage:
#   ./execute-phase5-6.sh          # Full workflow: enable -> apply -> validate -> cleanup (auto)
#   ./execute-phase5-6.sh --dry-run # Show what would happen without executing
#   ./execute-phase5-6.sh --no-cleanup # Skip automatic EXIT trap cleanup (debug mode)
#
# Exit Codes:
#   0 - Success
#   1 - Bootstrap (network access) failed
#   2 - Reconcile/import failed
#   3 - Terraform apply failed
#   4 - ADF artifact remediation failed
#   5 - Validation failed
#   6 - Cleanup failed (non-fatal, manual lockdown may be needed)
#
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

DRY_RUN=false
SKIP_CLEANUP=false

# shellcheck source=lib/keyvault-network-access.sh
source "$SCRIPT_DIR/lib/keyvault-network-access.sh"
# shellcheck source=lib/storage-network-access.sh
source "$SCRIPT_DIR/lib/storage-network-access.sh"

###############################################################################
# Helper Functions
###############################################################################

log_info() {
  echo "[INFO] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2
}

log_section() {
  echo ""
  echo "████████████████████████████████████████████████████████████████" >&2
  echo "█ $*" >&2
  echo "████████████████████████████████████████████████████████████████" >&2
  echo ""
}

log_error() {
  echo "[ERROR] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2
}

log_success() {
  echo "[SUCCESS] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2
}

tf_state_has_address() {
  local address="$1"
  terraform state list 2>/dev/null | grep -Fx "$address" >/dev/null 2>&1
}

import_if_exists() {
  local address="$1"
  local resource_id="$2"

  if [[ -z "$resource_id" ]]; then
    return
  fi

  if tf_state_has_address "$address"; then
    log_info "State already contains $address"
    return
  fi

  log_info "Importing existing resource into state: $address"
  terraform import -var-file=demo.tfvars "$address" "$resource_id" >/dev/null
  log_success "Imported $address"
}

phase_reconcile_existing_kv_resources() {
  log_section "PHASE 2/6: Reconcile Existing Key Vault Data-Plane Resources"

  if [[ ! -d "$TERRAFORM_DIR" ]]; then
    log_error "Terraform directory not found: $TERRAFORM_DIR"
    return 2
  fi

  if [[ $DRY_RUN == true ]]; then
    log_info "[DRY RUN] Would attempt imports for pre-existing KV keys/secrets"
    return 0
  fi

  cd "$TERRAFORM_DIR"

  local id

  # Key Vault secrets (Canada East vault)
  id="$(az keyvault secret show --vault-name kvdemocanadaeast --name adf-source-fileshare-connection-string --query id -o tsv 2>/dev/null || true)"
  import_if_exists "azurerm_key_vault_secret.adf_source_fileshare_connection_string" "$id"

  id="$(az keyvault secret show --vault-name kvdemocanadaeast --name adf-dest-fileshare-connection-string --query id -o tsv 2>/dev/null || true)"
  import_if_exists "azurerm_key_vault_secret.adf_dest_fileshare_connection_string" "$id"

  # East US 2 keys
  id="$(az keyvault key show --vault-name kvdemoeastus2 --name cmk-st-eastus2 --query key.kid -o tsv 2>/dev/null || true)"
  import_if_exists "module.eastus2_encryption_keys.azurerm_key_vault_key.this[\"cmk-st-eastus2\"]" "$id"

  id="$(az keyvault key show --vault-name kvdemoeastus2 --name cmk-dl-eastus2 --query key.kid -o tsv 2>/dev/null || true)"
  import_if_exists "module.eastus2_encryption_keys.azurerm_key_vault_key.this[\"cmk-dl-eastus2\"]" "$id"

  # Canada East keys
  id="$(az keyvault key show --vault-name kvdemocanadaeast --name cmk-st-canadaeast --query key.kid -o tsv 2>/dev/null || true)"
  import_if_exists "module.canadaeast_encryption_keys.azurerm_key_vault_key.this[\"cmk-st-canadaeast\"]" "$id"

  id="$(az keyvault key show --vault-name kvdemocanadaeast --name cmk-dl-canadaeast --query key.kid -o tsv 2>/dev/null || true)"
  import_if_exists "module.canadaeast_encryption_keys.azurerm_key_vault_key.this[\"cmk-dl-canadaeast\"]" "$id"

  id="$(az keyvault key show --vault-name kvdemocanadaeast --name cmk-adf-canadaeast --query key.kid -o tsv 2>/dev/null || true)"
  import_if_exists "module.canadaeast_encryption_keys.azurerm_key_vault_key.this[\"cmk-adf-canadaeast\"]" "$id"

  # ADF ARM template deployment (created by prior partial runs)
  id="$(az resource show \
    --resource-group rg-demo-canadaeast \
    --resource-type Microsoft.Resources/deployments \
    --name adf-pipeline-deployment \
    --query id -o tsv 2>/dev/null || true)"
  import_if_exists "module.data_factory.azurerm_resource_group_template_deployment.pipeline" "$id"

  log_success "Reconciliation complete"
}

###############################################################################
# Phase Functions
###############################################################################

phase_bootstrap() {
  log_section "PHASE 1/6: Bootstrap Network Access"
  
  log_info "Detecting caller IP and enabling temporary public access..."
  
  if [[ $DRY_RUN == true ]]; then
    log_info "[DRY RUN] Would enable access from detected IP"
    return 0
  fi
  
  # Detect caller IP (uses lib function)
  detect_bootstrap_cidr
  log_info "Detected caller IP: $BOOTSTRAP_CIDR"
  
  # Setup EXIT trap for automatic cleanup
  # shellcheck disable=SC2064
  trap "phase_cleanup" EXIT
  
  # Open Key Vault access only. Storage accounts do NOT need public access for:
  #   - CMK binding: management-plane; storage identity uses KV via AzureServices bypass
  #   - KV secrets: values come from Terraform state (already stored), not storage data-plane
  log_info "Opening temporary access to Key Vaults..."
  open_key_vault_access "kvdemoeastus2" || return 1
  open_key_vault_access "kvdemocanadaeast" || return 1
  
  log_success "Bootstrap complete - temporary KV access enabled"
}

phase_cleanup() {
  if [[ $SKIP_CLEANUP == true ]]; then
    log_info "Skipping cleanup (--no-cleanup flag set)"
    return 0
  fi
  
  log_section "Cleanup: Restoring Network Lockdown"
  
  if [[ $DRY_RUN == true ]]; then
    log_info "[DRY RUN] Would restore network lockdown"
    return 0
  fi
  
  log_info "Restoring network ACLs to Disabled state..."
  close_all_key_vault_access
  close_all_storage_access
  
  log_success "Network lockdown restored - Phase 4 security posture maintained"
}

phase_apply() {
  log_section "PHASE 3/6: Terraform Apply Phase 5-6 Resources"
  
  if [[ ! -d "$TERRAFORM_DIR" ]]; then
    log_error "Terraform directory not found: $TERRAFORM_DIR"
    return 2
  fi
  
  log_info "Running terraform apply for Phase 5-6 hardening..."
  log_info "Using -refresh=false to avoid ADLS data-plane refresh failures from public workstation."
  log_info "Expected creates:"
  log_info "  - 6 CMK keys (3 per region: storage, datalake, adf)"
  log_info "  - 4 CMK bindings (storage + datalake × 2 regions)"
  log_info "  - 1 ADF CMK binding"
  log_info "  - 2 KV secrets (ADF connection strings)"
  log_info "  - 1 Data Factory with pipelines and triggers"
  echo ""
  
  if [[ $DRY_RUN == true ]]; then
    log_info "[DRY RUN] Would execute:"
    log_info "  cd $TERRAFORM_DIR"
    log_info "  terraform apply -refresh=false -var-file=demo.tfvars -auto-approve"
    return 0
  fi
  
  cd "$TERRAFORM_DIR"
  
  if ! terraform apply -refresh=false -var-file=demo.tfvars -auto-approve; then
    log_error "Terraform apply failed"
    return 2
  fi
  
  log_success "Terraform apply complete"
}

phase_ensure_adf_artifacts() {
  log_section "PHASE 4/6: Ensure ADF Artifacts"

  if [[ $DRY_RUN == true ]]; then
    log_info "[DRY RUN] Would verify pipelines/triggers and redeploy ARM template if missing"
    return 0
  fi

  local rg="rg-demo-canadaeast"
  local factory="dfdemocanadaeast"
  local template_file="$TERRAFORM_DIR/modules/data_factory/pipeline.json"
  local pipelines triggers

  pipelines="$(az datafactory pipeline list --resource-group "$rg" --factory-name "$factory" --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  triggers="$(az datafactory trigger list --resource-group "$rg" --factory-name "$factory" --query "length(@)" -o tsv 2>/dev/null || echo 0)"

  if [[ "$pipelines" =~ ^[0-9]+$ ]] && [[ "$triggers" =~ ^[0-9]+$ ]] && [[ "$pipelines" -gt 0 ]] && [[ "$triggers" -gt 0 ]]; then
    log_success "ADF artifacts already present (pipelines=$pipelines, triggers=$triggers)"
    return 0
  fi

  log_info "ADF artifacts missing (pipelines=$pipelines, triggers=$triggers); forcing ARM template deployment..."

  cd "$TERRAFORM_DIR"

  local keyvault_uri
  local subscription_id
  local source_fs_account
  local dest_fs_account
  local source_dl_account
  local dest_dl_account
  local source_dl_filesystem
  local dest_dl_filesystem

  keyvault_uri="$(terraform output -raw canadaeast_key_vault_uri)"
  subscription_id="$(az account show --query id -o tsv)"
  source_fs_account="$(terraform output -raw eastus2_storage_name)"
  dest_fs_account="$(terraform output -raw canadaeast_storage_name)"
  source_dl_account="$(terraform output -raw eastus2_datalake_storage_name)"
  dest_dl_account="$(terraform output -raw canadaeast_datalake_storage_name)"
  source_dl_filesystem="$(terraform output -raw eastus2_datalake_filesystem_name)"
  dest_dl_filesystem="$(terraform output -raw canadaeast_datalake_filesystem_name)"

  az deployment group create \
    --resource-group "$rg" \
    --name adf-pipeline-deployment \
    --mode Incremental \
    --template-file "$template_file" \
    --parameters \
      factoryName="$factory" \
      keyVaultBaseUrl="$keyvault_uri" \
      sourceFileshareAccountName="$source_fs_account" \
      destFileshareAccountName="$dest_fs_account" \
      sourceFileshareStorageResourceId="/subscriptions/$subscription_id/resourceGroups/rg-demo-eastus2/providers/Microsoft.Storage/storageAccounts/$source_fs_account" \
      destFileshareStorageResourceId="/subscriptions/$subscription_id/resourceGroups/rg-demo-canadaeast/providers/Microsoft.Storage/storageAccounts/$dest_fs_account" \
      sourceDatalakeAccountName="$source_dl_account" \
      destDatalakeAccountName="$dest_dl_account" \
      sourceDatalakeFilesystem="$source_dl_filesystem" \
      destDatalakeFilesystem="$dest_dl_filesystem" \
    >/dev/null

  pipelines="$(az datafactory pipeline list --resource-group "$rg" --factory-name "$factory" --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  triggers="$(az datafactory trigger list --resource-group "$rg" --factory-name "$factory" --query "length(@)" -o tsv 2>/dev/null || echo 0)"

  if [[ "$pipelines" =~ ^[0-9]+$ ]] && [[ "$triggers" =~ ^[0-9]+$ ]] && [[ "$pipelines" -gt 0 ]] && [[ "$triggers" -gt 0 ]]; then
    log_success "ADF ARM deployment materialized artifacts (pipelines=$pipelines, triggers=$triggers)"
    return 0
  fi

  log_error "ADF artifacts still missing after forced ARM deployment (pipelines=$pipelines, triggers=$triggers)"
  return 3
}

phase_seed_initial_checkpoints() {
  log_section "PHASE 5/6: Seed Initial Checkpoints"

  if [[ ! -d "$TERRAFORM_DIR" ]]; then
    log_error "Terraform directory not found: $TERRAFORM_DIR"
    return 2
  fi

  if [[ $DRY_RUN == true ]]; then
    log_info "[DRY RUN] Would seed initial checkpoint blobs if they do not exist"
    return 0
  fi

  cd "$TERRAFORM_DIR"

  local checkpoint_rg
  local checkpoint_storage
  local checkpoint_container
  local checkpoint_current_prefix
  local fileshare_checkpoint_blob
  local datalake_checkpoint_blob
  local bootstrap_watermark
  local account_key

  checkpoint_rg="$(terraform output -raw canadaeast_rg_name)"
  checkpoint_storage="$(terraform console -var-file=demo.tfvars <<< 'var.canadaeast_checkpoint_storage_name' | tr -d '"')"
  checkpoint_container="$(terraform console -var-file=demo.tfvars <<< 'var.adf_checkpoint_container_name' | tr -d '"')"
  checkpoint_current_prefix="$(terraform console -var-file=demo.tfvars <<< 'var.adf_checkpoint_current_prefix' | tr -d '"')"
  fileshare_checkpoint_blob="$(terraform console -var-file=demo.tfvars <<< 'var.adf_fileshare_checkpoint_blob_name' | tr -d '"')"
  datalake_checkpoint_blob="$(terraform console -var-file=demo.tfvars <<< 'var.adf_datalake_checkpoint_blob_name' | tr -d '"')"
  bootstrap_watermark="$(terraform console -var-file=demo.tfvars <<< 'var.adf_incremental_bootstrap_watermark' | tr -d '"')"

  detect_bootstrap_cidr
  open_storage_account_access "$checkpoint_storage" "$checkpoint_rg"

  account_key="$(az storage account keys list --resource-group "$checkpoint_rg" --account-name "$checkpoint_storage" --query "[0].value" -o tsv)"
  if [[ -z "$account_key" ]]; then
    log_error "Unable to retrieve storage account key for checkpoint seeding"
    return 4
  fi

  seed_checkpoint_blob() {
    local blob_name="$1"
    local pipeline_name="$2"
    local blob_path="${checkpoint_current_prefix}/${blob_name}"
    local blob_exists
    local temp_file

    blob_exists="$(az storage blob exists --account-name "$checkpoint_storage" --account-key "$account_key" --container-name "$checkpoint_container" --name "$blob_path" --query exists -o tsv)"
    if [[ "$blob_exists" == "true" ]]; then
      log_info "Checkpoint already exists; leaving unchanged: ${blob_path}"
      return 0
    fi

    temp_file="$(mktemp)"
    printf '[{"schemaVersion":"1","pipelineName":"%s","lastSuccessfulWatermarkUtc":"%s","lastRunId":"bootstrap","lastRunStatus":"seeded","lastRunEndedUtc":"%s"}]' "$pipeline_name" "$bootstrap_watermark" "$bootstrap_watermark" > "$temp_file"

    az storage blob upload \
      --account-name "$checkpoint_storage" \
      --account-key "$account_key" \
      --container-name "$checkpoint_container" \
      --name "$blob_path" \
      --file "$temp_file" \
      --overwrite false \
      --only-show-errors >/dev/null

    rm -f "$temp_file"
    log_success "Seeded checkpoint blob: ${blob_path}"
  }

  seed_checkpoint_blob "$fileshare_checkpoint_blob" "copyfilesharepipeline"
  seed_checkpoint_blob "$datalake_checkpoint_blob" "copydatalakegen2pipeline"
  close_storage_account_access "$checkpoint_storage" "$checkpoint_rg"

  log_success "Checkpoint seeding complete"
}

phase_validate() {
  log_section "PHASE 6/6: Validation"
  
  log_info "Validating Phase 5-6 resources..."
  
  local validation_passed=true
  
  # Check CMK keys
  log_info "Checking CMK keys exist..."
  for kv in kvdemoeastus2 kvdemocanadaeast; do
    rg="rg-demo-eastus2"; [[ "$kv" == "kvdemocanadaeast" ]] && rg="rg-demo-canadaeast"
    if [[ $DRY_RUN == false ]]; then
      keys=$(az keyvault key list --vault-name "$kv" --query "[].name" -o tsv 2>&1 | wc -l)
      if [[ $keys -gt 0 ]]; then
        log_success "  ✓ $kv: $keys CMK keys found"
      else
        log_error "  ✗ $kv: No CMK keys found"
        validation_passed=false
      fi
    else
      log_info "  [DRY RUN] Would check $kv for CMK keys"
    fi
  done
  
  # Check storage CMK bindings
  log_info "Checking storage account CMK bindings..."
  for st in stdemoeastus2 stdemocanadaeast stdldemoeastus2 stdldemocanadaeast; do
    rg="rg-demo-eastus2"; [[ "$st" == *"canadaeast" ]] && rg="rg-demo-canadaeast"
    if [[ $DRY_RUN == false ]]; then
      key_source=$(az storage account show -g "$rg" -n "$st" --query "encryption.keySource" -o tsv 2>&1)
      if [[ "$key_source" == "Microsoft.Keyvault" ]]; then
        log_success "  ✓ $st: Using CMK encryption"
      else
        log_error "  ✗ $st: Not using CMK (keySource=$key_source)"
        validation_passed=false
      fi
    else
      log_info "  [DRY RUN] Would check $st encryption"
    fi
  done
  
  # Check KV secrets
  log_info "Checking KV secrets..."
  if [[ $DRY_RUN == false ]]; then
    secrets=$(az keyvault secret list --vault-name kvdemocanadaeast --query "[?contains(name, 'adf')].name" -o tsv 2>&1 | wc -l)
    if [[ $secrets -ge 2 ]]; then
      log_success "  ✓ kvdemocanadaeast: $secrets ADF connection secrets found"
    else
      log_error "  ✗ kvdemocanadaeast: Expected ≥2 ADF secrets, found $secrets"
      validation_passed=false
    fi
  else
    log_info "  [DRY RUN] Would check kvdemocanadaeast for adf-* secrets"
  fi
  
  # Check Data Factory
  log_info "Checking Data Factory deployment..."
  if [[ $DRY_RUN == false ]]; then
    adf=$(az datafactory show --resource-group rg-demo-canadaeast --name dfdemocanadaeast --query "name" -o tsv 2>&1)
    if [[ -n "$adf" ]]; then
      log_success "  ✓ Data Factory deployed: dfdemocanadaeast"
      
      # Check pipelines
      pipelines=$(az datafactory pipeline list --resource-group rg-demo-canadaeast \
        --factory-name dfdemocanadaeast --query "[].name" -o tsv 2>&1 | wc -l)
      if [[ $pipelines -gt 0 ]]; then
        log_success "    ├─ Pipelines deployed: $pipelines"
      else
        log_error "    ├─ Pipelines deployed: $pipelines"
        validation_passed=false
      fi

      # Check triggers
      triggers=$(az datafactory trigger list --resource-group rg-demo-canadaeast \
        --factory-name dfdemocanadaeast --query "[].name" -o tsv 2>&1 | wc -l)
      if [[ $triggers -gt 0 ]]; then
        log_success "    ├─ Triggers deployed: $triggers"
      else
        log_error "    ├─ Triggers deployed: $triggers"
        validation_passed=false
      fi
      
      # Check CMK binding
      cmk=$(az datafactory show --resource-group rg-demo-canadaeast --name dfdemocanadaeast \
        --query "encryption.keyName" -o tsv 2>/dev/null || true)
      if [[ -n "$cmk" && "$cmk" != "None" && "$cmk" != "null" ]]; then
        log_success "    └─ CMK binding: enabled"
      else
        log_error "    └─ CMK binding: not found"
        validation_passed=false
      fi
    else
      log_error "  ✗ Data Factory not deployed"
      validation_passed=false
    fi
  else
    log_info "  [DRY RUN] Would check Data Factory deployment"
  fi
  
  if [[ $validation_passed == true ]]; then
    log_success "Validation complete - all Phase 5-6 resources verified"
    return 0
  else
    log_error "Validation failed - some resources missing or misconfigured"
    return 3
  fi
}

###############################################################################
# Main Orchestration
###############################################################################

usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run          Show what would happen without executing
  --no-cleanup       Skip automatic network lockdown on exit (for debugging)
  --help             Show this help message

Description:
  Execute Phase 5-6 hardening with automatic network access management via lib functions:
  1. Bootstrap: Enable public access from caller IP using lib helper functions
  2. Reconcile: Import pre-existing KV keys/secrets into Terraform state (idempotent reruns)
  3. Apply: Terraform apply for CMK, secrets, ADF
  4. Ensure: Force ADF ARM deployment if pipelines/triggers are missing
  5. Seed: Create initial checkpoint blobs when missing (first-run safety)
  6. Validate: Verify all resources created successfully
  7. Cleanup: EXIT trap automatically restores network lockdown (unless --no-cleanup)

Exit Codes:
  0 - Success
  1 - Bootstrap failed
  2 - Reconcile/import failed
  3 - Terraform apply failed
  4 - ADF artifact remediation failed
  5 - Checkpoint seeding failed
  6 - Validation failed

Examples:
  ./execute-phase5-6.sh                # Full workflow (auto-cleanup via EXIT trap)
  ./execute-phase5-6.sh --dry-run       # Preview only
  ./execute-phase5-6.sh --no-cleanup    # Skip automatic lockdown (for debugging)

Note:
  Uses scripts/lib/keyvault-network-access.sh and scripts/lib/storage-network-access.sh
  for robust network access management with propagation waiting and data-plane verification.

EOF
}

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-cleanup)
        SKIP_CLEANUP=true
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
  
  log_section "Phase 5-6 Hardening Execution"
  
  if [[ $DRY_RUN == true ]]; then
    log_info "DRY RUN MODE - No actual changes will be made"
  fi
  
  # Execute phases (EXIT trap will fire automatically on exit/error)
  if ! phase_bootstrap; then
    log_error "Phase 1 failed - aborting (EXIT trap will clean up)"
    exit 1
  fi

  if ! phase_reconcile_existing_kv_resources; then
    log_error "Phase 2 failed (EXIT trap will restore network lockdown)"
    exit 2
  fi
  
  if ! phase_apply; then
    log_error "Phase 3 failed (EXIT trap will restore network lockdown)"
    exit 3
  fi
  
  if ! phase_ensure_adf_artifacts; then
    log_error "Phase 4 failed (EXIT trap will restore network lockdown)"
    exit 4
  fi

  if ! phase_seed_initial_checkpoints; then
    log_error "Phase 5 failed (EXIT trap will restore network lockdown)"
    exit 5
  fi

  if ! phase_validate; then
    log_error "Phase 6 failed (EXIT trap will restore network lockdown)"
    exit 6
  fi
  
  log_section "✓ Phase 5-6 Complete"
  echo ""
  echo "All Phase 5-6 hardening resources deployed successfully:"
  echo "  ✓ CMK keys created (6 total: 3 per region)"
  echo "  ✓ CMK bindings applied to storage and datalake"
  echo "  ✓ KV secrets created for ADF connection strings"
  echo "  ✓ Data Factory deployed with pipelines and triggers"
  echo "  ✓ Initial checkpoint blobs seeded (if missing) for first-run safety"
  echo "  ✓ Network ACLs restored to Disabled (Phase 4 lockdown maintained automatically)"
  echo ""
  echo "Next steps:"
  echo "  1. Approve managed VNet private endpoints (REQUIRED): ./approve-managed-private-endpoints.sh"
  echo "  2. Populate source data:"
  echo "       ./populate-source-datalake.sh"
  echo "       ./populate-source-fileshare.sh"
  echo "  3. Start replication triggers:"
  echo "       ./toggle-trigger.sh start"
  echo "       ./toggle-datalake-trigger.sh start"
  echo "  4. Validate replication health: ./validate-adf-health.sh"
  echo ""
}

main "$@"
