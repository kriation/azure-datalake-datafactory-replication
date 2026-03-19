#!/usr/bin/env bash
# test-phase3-cmk.sh
# Deploys, validates, and destroys Phase 3 CMK and Key Vault RBAC resources.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
TFVARS_FILE="demo.tfvars"
KEEP_RESOURCES=false
CLEANUP_ALL=false
AUTO_APPROVE=true
DEPLOYED=false
CLEANUP_PHASE=false
BOOTSTRAP_NETWORK_OPEN=false
BOOTSTRAP_CIDR=""
BOOTSTRAP_EAST_RG=""
BOOTSTRAP_CANADA_RG=""
BOOTSTRAP_EAST_KV=""
BOOTSTRAP_CANADA_KV=""
BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS=180
BOOTSTRAP_PROPAGATION_POLL_SECONDS=5
BOOTSTRAP_POST_READY_SLEEP_SECONDS=20

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --tfvars FILE      Terraform var-file name under terraform/ (default: demo.tfvars)
  -k, --keep             Keep deployed resources (skip destroy)
  --cleanup-phase        Destroy Phase 3 resources only (skip deploy/validate)
  --cleanup-all          Destroy Phase 3 and all prior prerequisites (implies --cleanup-phase)
  --no-auto-approve      Disable -auto-approve in terraform apply/destroy
  -h, --help             Show this help

Examples:
  ./scripts/test-phase3-cmk.sh
  ./scripts/test-phase3-cmk.sh --keep
  ./scripts/test-phase3-cmk.sh --cleanup-phase
  ./scripts/test-phase3-cmk.sh --cleanup-all
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--tfvars)
      TFVARS_FILE="$2"
      shift 2
      ;;
    -k|--keep)
      KEEP_RESOURCES=true
      shift
      ;;
    --cleanup-phase)
      CLEANUP_PHASE=true
      shift
      ;;
    --cleanup-all)
      CLEANUP_ALL=true
      shift
      ;;
    --no-auto-approve)
      AUTO_APPROVE=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

TFVARS_PATH="$TF_DIR/$TFVARS_FILE"
if [[ ! -f "$TFVARS_PATH" ]]; then
  echo "Error: var-file not found: $TFVARS_PATH"
  exit 1
fi

for cmd in terraform az jq grep awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: required command 'curl' is not installed or not in PATH."
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not authenticated. Run 'az login' first."
  exit 1
fi

TF_APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" == true ]]; then
  TF_APPROVE_ARGS+=("-auto-approve")
fi

tf() {
  terraform -chdir="$TF_DIR" "$@"
}

phase3_bootstrap_tf_args() {
  if [[ "$BOOTSTRAP_NETWORK_OPEN" != true ]]; then
    return
  fi

  if [[ -z "$BOOTSTRAP_CIDR" ]]; then
    echo "Error: bootstrap CIDR is not set while bootstrap mode is enabled."
    exit 1
  fi

  printf '%s\n' \
    "-var=key_vault_public_network_access_enabled=true" \
    "-var=key_vault_ip_rules=[\"${BOOTSTRAP_CIDR}\"]"
}

tfvar_string() {
  local variable_name="$1"
  grep -E "^[[:space:]]*${variable_name}[[:space:]]*=" "$TFVARS_PATH" | head -n 1 | awk -F'"' '{print $2}'
}

tf_output_or_default() {
  local output_name="$1"
  local default_value="$2"
  local output_value=""

  output_value="$(tf output -raw "$output_name" 2>/dev/null || true)"
  if [[ -n "$output_value" ]]; then
    echo "$output_value"
    return
  fi

  echo "$default_value"
}

detect_bootstrap_cidr() {
  local public_ip

  if [[ -n "$BOOTSTRAP_CIDR" ]]; then
    return
  fi

  public_ip="$(curl -fsSL https://api.ipify.org)"
  if [[ -z "$public_ip" ]]; then
    echo "Error: unable to determine the current public IP for Phase 3 Key Vault bootstrap access."
    exit 1
  fi

  BOOTSTRAP_CIDR="${public_ip}/32"
}

wait_for_kv_bootstrap_network_ready() {
  local kv_name="$1"
  local kv_rg="$2"
  local elapsed=0
  local pna_state=""
  local ip_rule_count=""

  while [[ "$elapsed" -lt "$BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS" ]]; do
    pna_state="$(az keyvault show --name "$kv_name" --resource-group "$kv_rg" --query properties.publicNetworkAccess -o tsv 2>/dev/null || true)"
    ip_rule_count="$(az keyvault show --name "$kv_name" --resource-group "$kv_rg" --query "length(properties.networkAcls.ipRules[?value=='${BOOTSTRAP_CIDR}'])" -o tsv 2>/dev/null || true)"

    if [[ "$pna_state" == "Enabled" && "$ip_rule_count" != "" && "$ip_rule_count" -ge 1 ]]; then
      return
    fi

    sleep "$BOOTSTRAP_PROPAGATION_POLL_SECONDS"
    elapsed=$((elapsed + BOOTSTRAP_PROPAGATION_POLL_SECONDS))
  done

  echo "Error: temporary Key Vault network bootstrap did not propagate in time for '$kv_name'."
  echo "       Last observed state: publicNetworkAccess='${pna_state}', matchingIpRules='${ip_rule_count}'."
  exit 1
}

open_key_vault_bootstrap_access() {
  local east_public_access
  local canada_public_access

  detect_bootstrap_cidr

  BOOTSTRAP_EAST_RG="$(tf output -raw eastus2_rg_name 2>/dev/null || true)"
  BOOTSTRAP_CANADA_RG="$(tf output -raw canadaeast_rg_name 2>/dev/null || true)"
  BOOTSTRAP_EAST_KV="$(tf output -raw eastus2_key_vault_name 2>/dev/null || true)"
  BOOTSTRAP_CANADA_KV="$(tf output -raw canadaeast_key_vault_name 2>/dev/null || true)"

  if [[ -z "$BOOTSTRAP_EAST_RG" || -z "$BOOTSTRAP_CANADA_RG" || -z "$BOOTSTRAP_EAST_KV" || -z "$BOOTSTRAP_CANADA_KV" ]]; then
    echo "[WARN] Unable to resolve Key Vault names/resource groups from Terraform outputs; skipping temporary bootstrap access update."
    return 1
  fi

  if ! az keyvault show --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" >/dev/null 2>&1; then
    echo "[WARN] East US 2 Key Vault '$BOOTSTRAP_EAST_KV' not found; skipping temporary bootstrap access update."
    return 1
  fi

  if ! az keyvault show --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" >/dev/null 2>&1; then
    echo "[WARN] Canada East Key Vault '$BOOTSTRAP_CANADA_KV' not found; skipping temporary bootstrap access update."
    return 1
  fi

  echo "[INFO] Temporarily enabling Key Vault public access for the current operator IP (${BOOTSTRAP_CIDR}) for data plane operations..."
  echo "[INFO] This exception is temporary and will be removed before the script completes."

  az keyvault update --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --public-network-access Enabled >/dev/null
  az keyvault update --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --public-network-access Enabled >/dev/null
  az keyvault network-rule add --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --ip-address "$BOOTSTRAP_CIDR" >/dev/null
  az keyvault network-rule add --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --ip-address "$BOOTSTRAP_CIDR" >/dev/null

  east_public_access="$(az keyvault show --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --query properties.publicNetworkAccess -o tsv)"
  canada_public_access="$(az keyvault show --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --query properties.publicNetworkAccess -o tsv)"
  if [[ "$east_public_access" != "Enabled" || "$canada_public_access" != "Enabled" ]]; then
    echo "Error: failed to enable temporary public network access on Key Vaults for CMK bootstrap."
    exit 1
  fi

  echo "[INFO] Waiting for temporary Key Vault network access propagation..."
  wait_for_kv_bootstrap_network_ready "$BOOTSTRAP_EAST_KV" "$BOOTSTRAP_EAST_RG"
  wait_for_kv_bootstrap_network_ready "$BOOTSTRAP_CANADA_KV" "$BOOTSTRAP_CANADA_RG"

  # The Key Vault data plane can lag behind management-plane ACL state.
  sleep "$BOOTSTRAP_POST_READY_SLEEP_SECONDS"

  BOOTSTRAP_NETWORK_OPEN=true
}

restore_key_vault_lockdown() {
  if [[ "$BOOTSTRAP_NETWORK_OPEN" != true ]]; then
    return
  fi

  echo "[INFO] Restoring Key Vault public network access to disabled and clearing temporary operator IP rules..."
  az keyvault network-rule remove --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --ip-address "$BOOTSTRAP_CIDR" >/dev/null 2>&1 || true
  az keyvault network-rule remove --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --ip-address "$BOOTSTRAP_CIDR" >/dev/null 2>&1 || true
  az keyvault update --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --public-network-access Disabled >/dev/null
  az keyvault update --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --public-network-access Disabled >/dev/null

  BOOTSTRAP_NETWORK_OPEN=false
}

destroy_phase3() {
  local opened_for_phase3_destroy=false

  # Key deletion is a Key Vault data-plane operation. Ensure temporary caller access before destroy.
  if [[ "$BOOTSTRAP_NETWORK_OPEN" != true ]]; then
    if open_key_vault_bootstrap_access; then
      opened_for_phase3_destroy=true
    else
      echo "[WARN] Proceeding with Phase 3 key destroy without temporary bootstrap access; Key Vault data-plane deletes may fail if vaults are private-only."
    fi
  fi

  echo "[INFO] Destroying Phase 3 encryption key modules..."
  tf destroy \
    -target=module.eastus2_encryption_keys \
    -target=module.canadaeast_encryption_keys \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true

  if [[ "$opened_for_phase3_destroy" == true ]]; then
    restore_key_vault_lockdown
  fi

  echo "[INFO] Destroying Phase 3 Key Vault RBAC and Data Factory identity resources..."
  tf destroy \
    -target=time_sleep.eastus2_key_vault_rbac_propagation \
    -target=time_sleep.canadaeast_key_vault_rbac_propagation \
    -target=azurerm_role_assignment.eastus2_key_vault_admin_current \
    -target=azurerm_role_assignment.canadaeast_key_vault_admin_current \
    -target=azurerm_role_assignment.canadaeast_data_factory_key_vault_crypto_user \
    -target=module.data_factory_identity \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true

  if [[ "$CLEANUP_ALL" == true ]]; then
    echo "[INFO] Destroying Phase 2 key vault modules..."
    tf destroy \
      -target=module.eastus2_key_vault \
      -target=module.canadaeast_key_vault \
      -var-file="$TFVARS_FILE" \
      "${TF_APPROVE_ARGS[@]}" || true

    echo "[INFO] Destroying Phase 1 network modules..."
    tf destroy \
      -target=module.eastus2_network \
      -target=module.canadaeast_network \
      -var-file="$TFVARS_FILE" \
      "${TF_APPROVE_ARGS[@]}" || true

    echo "[INFO] Destroying resource groups..."
    tf destroy \
      -target=module.eastus2_rg \
      -target=module.canadaeast_rg \
      -var-file="$TFVARS_FILE" \
      "${TF_APPROVE_ARGS[@]}" || true
  fi
}

cleanup() {
  local exit_code="$1"

  if [[ "$BOOTSTRAP_NETWORK_OPEN" == true ]]; then
    restore_key_vault_lockdown
  fi

  if [[ "$KEEP_RESOURCES" == true ]]; then
    echo "[INFO] --keep set, skipping destroy."
    return
  fi

  if [[ "$DEPLOYED" != true ]]; then
    return
  fi

  echo "[INFO] Validation failed or run completed — rolling back Phase 3 deployment..."
  destroy_phase3

  if [[ "$exit_code" -eq 0 ]]; then
    echo "[PASS] Phase 3 test completed and cleanup finished."
  else
    echo "[WARN] Phase 3 test failed; rollback attempted. Review errors above."
  fi
}

trap 'cleanup $?' EXIT

echo "[INFO] Initializing Terraform..."
tf init -upgrade=false >/dev/null

if [[ "$CLEANUP_ALL" == true ]]; then
  CLEANUP_PHASE=true
fi

if [[ "$CLEANUP_PHASE" == true ]]; then
  destroy_phase3
  echo "[PASS] Cleanup operation completed."
  exit 0
fi

echo "[INFO] Applying Phase 1 prerequisites (resource groups + network)..."
tf apply -target=module.eastus2_rg -target=module.canadaeast_rg -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"
tf apply -target=module.eastus2_network -target=module.canadaeast_network -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

echo "[INFO] Applying Phase 2 prerequisites (Key Vaults)..."
tf apply -target=module.eastus2_key_vault -target=module.canadaeast_key_vault -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

open_key_vault_bootstrap_access

echo "[INFO] Applying Data Factory identity prerequisite..."
tf apply -target=module.data_factory_identity -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

echo "[INFO] Applying Phase 3 CMK and RBAC resources..."
PHASE3_APPLY_ARGS=("-var-file=$TFVARS_FILE")
if [[ "$BOOTSTRAP_NETWORK_OPEN" == true ]]; then
  while IFS= read -r arg; do
    PHASE3_APPLY_ARGS+=("$arg")
  done < <(phase3_bootstrap_tf_args)
fi

tf apply \
  -target=azurerm_role_assignment.eastus2_key_vault_admin_current \
  -target=azurerm_role_assignment.canadaeast_key_vault_admin_current \
  -target=azurerm_role_assignment.canadaeast_data_factory_key_vault_crypto_user \
  -target=time_sleep.eastus2_key_vault_rbac_propagation \
  -target=time_sleep.canadaeast_key_vault_rbac_propagation \
  -target=module.eastus2_encryption_keys \
  -target=module.canadaeast_encryption_keys \
  "${PHASE3_APPLY_ARGS[@]}" \
  "${TF_APPROVE_ARGS[@]}"
DEPLOYED=true

echo "[INFO] Collecting outputs for validation..."
EAST_RG="$(tf output -raw eastus2_rg_name)"
CANADA_RG="$(tf output -raw canadaeast_rg_name)"
EAST_KV="$(tf output -raw eastus2_key_vault_name)"
CANADA_KV="$(tf output -raw canadaeast_key_vault_name)"
CURRENT_OPERATOR_OBJECT_ID="$(tf output -raw current_operator_object_id)"
DATA_FACTORY_PRINCIPAL_ID="$(tf output -raw data_factory_principal_id)"
ADMIN_ROLE_NAME="$(tf_output_or_default key_vault_admin_role_definition_name "Key Vault Administrator")"
CRYPTO_ROLE_NAME="$(tf_output_or_default key_vault_crypto_user_role_definition_name "Key Vault Crypto Service Encryption User")"
EAST_STORAGE_CMK_KEY_ID="$(tf output -raw eastus2_storage_cmk_key_id)"
EAST_DATALAKE_CMK_KEY_ID="$(tf output -raw eastus2_datalake_cmk_key_id)"
CANADA_STORAGE_CMK_KEY_ID="$(tf output -raw canadaeast_storage_cmk_key_id)"
CANADA_DATALAKE_CMK_KEY_ID="$(tf output -raw canadaeast_datalake_cmk_key_id)"
CANADA_DATA_FACTORY_CMK_KEY_ID="$(tf output -raw canadaeast_data_factory_cmk_key_id)"

EAST_STORAGE_CMK_NAME="$(tfvar_string eastus2_storage_cmk_name)"
EAST_DATALAKE_CMK_NAME="$(tfvar_string eastus2_datalake_cmk_name)"
CANADA_STORAGE_CMK_NAME="$(tfvar_string canadaeast_storage_cmk_name)"
CANADA_DATALAKE_CMK_NAME="$(tfvar_string canadaeast_datalake_cmk_name)"
CANADA_DATA_FACTORY_CMK_NAME="$(tfvar_string canadaeast_data_factory_cmk_name)"

validate_key_exists() {
  local key_id="$1"
  local key_name="$2"
  local enabled_state

  if ! az keyvault key show --id "$key_id" --query key.kid -o tsv >/dev/null 2>&1; then
    echo "Error: expected CMK '$key_name' to exist, but it was not found via Azure CLI."
    exit 1
  fi

  enabled_state="$(az keyvault key show --id "$key_id" --query attributes.enabled -o tsv)"
  if [[ "$enabled_state" != "true" ]]; then
    echo "Error: expected CMK '$key_name' to be enabled but got '$enabled_state'."
    exit 1
  fi
}

validate_role_assignment() {
  local scope="$1"
  local principal_id="$2"
  local role_name="$3"
  local label="$4"
  local assignment_count

  assignment_count="$(az role assignment list --scope "$scope" --assignee-object-id "$principal_id" --query "[?roleDefinitionName=='$role_name'] | length(@)" -o tsv)"
  if [[ "$assignment_count" -lt 1 ]]; then
    echo "Error: expected role assignment '$role_name' for $label but none was found."
    exit 1
  fi
}

echo "[INFO] Validating CMK existence and enabled state..."
validate_key_exists "$EAST_STORAGE_CMK_KEY_ID" "$EAST_STORAGE_CMK_NAME"
validate_key_exists "$EAST_DATALAKE_CMK_KEY_ID" "$EAST_DATALAKE_CMK_NAME"
validate_key_exists "$CANADA_STORAGE_CMK_KEY_ID" "$CANADA_STORAGE_CMK_NAME"
validate_key_exists "$CANADA_DATALAKE_CMK_KEY_ID" "$CANADA_DATALAKE_CMK_NAME"
validate_key_exists "$CANADA_DATA_FACTORY_CMK_KEY_ID" "$CANADA_DATA_FACTORY_CMK_NAME"

echo "[INFO] Validating Key Vault RBAC assignments..."
EAST_VAULT_ID="$(az keyvault show --name "$EAST_KV" --resource-group "$EAST_RG" --query id -o tsv)"
CANADA_VAULT_ID="$(az keyvault show --name "$CANADA_KV" --resource-group "$CANADA_RG" --query id -o tsv)"
validate_role_assignment "$EAST_VAULT_ID" "$CURRENT_OPERATOR_OBJECT_ID" "$ADMIN_ROLE_NAME" "the current operator on East US 2 Key Vault"
validate_role_assignment "$CANADA_VAULT_ID" "$CURRENT_OPERATOR_OBJECT_ID" "$ADMIN_ROLE_NAME" "the current operator on Canada East Key Vault"
validate_role_assignment "$CANADA_VAULT_ID" "$DATA_FACTORY_PRINCIPAL_ID" "$CRYPTO_ROLE_NAME" "the Data Factory identity on Canada East Key Vault"

restore_key_vault_lockdown

echo "[INFO] Validating Key Vault lockdown restoration..."
EAST_PUBLIC_ACCESS="$(az keyvault show --name "$EAST_KV" --resource-group "$EAST_RG" --query properties.publicNetworkAccess -o tsv)"
CANADA_PUBLIC_ACCESS="$(az keyvault show --name "$CANADA_KV" --resource-group "$CANADA_RG" --query properties.publicNetworkAccess -o tsv)"

if [[ "$EAST_PUBLIC_ACCESS" != "Disabled" ]]; then
  echo "Error: East US 2 Key Vault public network access expected Disabled after CMK bootstrap but got '$EAST_PUBLIC_ACCESS'."
  exit 1
fi

if [[ "$CANADA_PUBLIC_ACCESS" != "Disabled" ]]; then
  echo "Error: Canada East Key Vault public network access expected Disabled after CMK bootstrap but got '$CANADA_PUBLIC_ACCESS'."
  exit 1
fi

echo "[PASS] Phase 3 deploy and validation succeeded."