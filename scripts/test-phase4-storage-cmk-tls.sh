#!/usr/bin/env bash
# test-phase4-storage-cmk-tls.sh
# Deploys, validates, and destroys Phase 4 storage CMK and TLS hardening resources.

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
BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS=120
BOOTSTRAP_PROPAGATION_POLL_SECONDS=5
BOOTSTRAP_POST_READY_SLEEP_SECONDS=5
STORAGE_BOOTSTRAP_OPEN=false
STORAGE_BOOTSTRAP_EAST_RG=""
STORAGE_BOOTSTRAP_CANADA_RG=""
STORAGE_BOOTSTRAP_EAST_STORAGE=""
STORAGE_BOOTSTRAP_CANADA_STORAGE=""
STORAGE_BOOTSTRAP_EAST_DATALAKE=""
STORAGE_BOOTSTRAP_CANADA_DATALAKE=""
STORAGE_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS=120
STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS=5
STORAGE_BOOTSTRAP_POST_READY_SLEEP_SECONDS=5
STORAGE_OPERATOR_RBAC_OPEN=false
STORAGE_OPERATOR_OBJECT_ID=""
STORAGE_OPERATOR_ASSIGNMENT_EAST_ID=""
STORAGE_OPERATOR_ASSIGNMENT_CANADA_ID=""
STORAGE_DATA_PLANE_TIMEOUT_SECONDS=180
STORAGE_DATA_PLANE_POLL_SECONDS=5

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --tfvars FILE      Terraform var-file name under terraform/ (default: demo.tfvars)
  -k, --keep             Keep deployed resources (skip destroy)
  --cleanup-phase        Destroy Phase 4 resources only (skip deploy/validate)
  --cleanup-all          Destroy Phase 4 and Phase 3 resources; retain Key Vaults and prerequisites (implies --cleanup-phase)
  --no-auto-approve      Disable -auto-approve in terraform apply/destroy
  -h, --help             Show this help

Examples:
  ./scripts/test-phase4-storage-cmk-tls.sh
  ./scripts/test-phase4-storage-cmk-tls.sh --keep
  ./scripts/test-phase4-storage-cmk-tls.sh --cleanup-phase
  ./scripts/test-phase4-storage-cmk-tls.sh --cleanup-all
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

if [[ ! -x "$REPO_ROOT/scripts/test-phase3-cmk.sh" ]]; then
  echo "Error: prerequisite script '$REPO_ROOT/scripts/test-phase3-cmk.sh' not found or not executable."
  exit 1
fi

TF_APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" == true ]]; then
  TF_APPROVE_ARGS+=("-auto-approve")
fi

PHASE3_ARGS=()
if [[ "$AUTO_APPROVE" == false ]]; then
  PHASE3_ARGS+=("--no-auto-approve")
fi


tf() {
  terraform -chdir="$TF_DIR" "$@"
}

import_resource_if_exists() {
  local tf_resource="$1"
  local azure_id="$2"

  if tf state show "$tf_resource" >/dev/null 2>&1; then
    return
  fi

  # Verify the resource actually exists in Azure before importing
  if ! az resource show --ids "$azure_id" >/dev/null 2>&1; then
    return
  fi

  echo "[INFO] Importing existing resource '$tf_resource' into Terraform state..."
  tf import -var-file="$TFVARS_FILE" "$tf_resource" "$azure_id"
}

import_storage_accounts_if_needed() {
  local subscription_id
  subscription_id="$(az account show --query id -o tsv)"

  load_storage_bootstrap_targets

  import_resource_if_exists \
    "module.eastus2_storage.azurerm_storage_account.this" \
    "/subscriptions/${subscription_id}/resourceGroups/${STORAGE_BOOTSTRAP_EAST_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_BOOTSTRAP_EAST_STORAGE}"

  import_resource_if_exists \
    "module.canadaeast_storage.azurerm_storage_account.this" \
    "/subscriptions/${subscription_id}/resourceGroups/${STORAGE_BOOTSTRAP_CANADA_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_BOOTSTRAP_CANADA_STORAGE}"

  import_resource_if_exists \
    "module.eastus2_datalake.azurerm_storage_account.this" \
    "/subscriptions/${subscription_id}/resourceGroups/${STORAGE_BOOTSTRAP_EAST_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_BOOTSTRAP_EAST_DATALAKE}"

  import_resource_if_exists \
    "module.canadaeast_datalake.azurerm_storage_account.this" \
    "/subscriptions/${subscription_id}/resourceGroups/${STORAGE_BOOTSTRAP_CANADA_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_BOOTSTRAP_CANADA_DATALAKE}"

  # Import file shares if their parent accounts are now in state
  import_resource_if_exists \
    "module.eastus2_storage.azurerm_storage_share.fileshare" \
    "/subscriptions/${subscription_id}/resourceGroups/${STORAGE_BOOTSTRAP_EAST_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_BOOTSTRAP_EAST_STORAGE}/fileServices/default/shares/fileshare"

  import_resource_if_exists \
    "module.canadaeast_storage.azurerm_storage_share.fileshare" \
    "/subscriptions/${subscription_id}/resourceGroups/${STORAGE_BOOTSTRAP_CANADA_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_BOOTSTRAP_CANADA_STORAGE}/fileServices/default/shares/fileshare"
}

tfvar_string() {
  local variable_name="$1"
  local line

  line="$(grep -E "^[[:space:]]*${variable_name}[[:space:]]*=" "$TFVARS_PATH" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi

  echo "$line" | awk -F'"' '{print $2}'
}

tfvar_bool() {
  local variable_name="$1"
  local line

  line="$(grep -E "^[[:space:]]*${variable_name}[[:space:]]*=" "$TFVARS_PATH" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi

  echo "$line" | awk -F'= *' '{print $2}' | tr -d '[:space:]'
}

require_phase4_key_vault_prerequisites() {
  local purge_protection_enabled

  purge_protection_enabled="$(tfvar_bool key_vault_purge_protection_enabled || true)"
  if [[ -z "$purge_protection_enabled" ]]; then
    echo "Error: missing required setting 'key_vault_purge_protection_enabled' in terraform/${TFVARS_FILE}."
    echo "       Set it to true for Phase 4 storage CMK binding support."
    exit 1
  fi

  if [[ "$purge_protection_enabled" != "true" ]]; then
    echo "Error: Phase 4 storage CMK bindings require 'key_vault_purge_protection_enabled = true'."
    echo "       Azure Storage will not bind to CMKs in a Key Vault without purge protection enabled."
    echo "       Update terraform/${TFVARS_FILE}, re-apply the Key Vault phase, and re-run Phase 4."
    echo "       Note: enabling purge protection is irreversible for an existing vault and changes teardown behavior for reuse of the same vault names."
    exit 1
  fi
}

detect_bootstrap_cidr() {
  local public_ip

  if [[ -n "$BOOTSTRAP_CIDR" ]]; then
    return
  fi

  public_ip="$(curl -fsSL https://api.ipify.org)"
  if [[ -z "$public_ip" ]]; then
    echo "Error: unable to determine the current public IP for Phase 4 Key Vault bootstrap access."
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

  echo "[INFO] Temporarily enabling Key Vault public access for the current operator IP (${BOOTSTRAP_CIDR}) for Phase 4 refresh and CMK binding checks..."
  echo "[INFO] This exception is temporary and will be removed before the script completes."

  az keyvault update --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --public-network-access Enabled >/dev/null
  az keyvault update --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --public-network-access Enabled >/dev/null
  az keyvault network-rule add --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --ip-address "$BOOTSTRAP_CIDR" >/dev/null
  az keyvault network-rule add --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --ip-address "$BOOTSTRAP_CIDR" >/dev/null

  east_public_access="$(az keyvault show --name "$BOOTSTRAP_EAST_KV" --resource-group "$BOOTSTRAP_EAST_RG" --query properties.publicNetworkAccess -o tsv)"
  canada_public_access="$(az keyvault show --name "$BOOTSTRAP_CANADA_KV" --resource-group "$BOOTSTRAP_CANADA_RG" --query properties.publicNetworkAccess -o tsv)"
  if [[ "$east_public_access" != "Enabled" || "$canada_public_access" != "Enabled" ]]; then
    echo "Error: failed to enable temporary public network access on Key Vaults for Phase 4 operations."
    exit 1
  fi

  echo "[INFO] Waiting for temporary Key Vault network access propagation..."
  wait_for_kv_bootstrap_network_ready "$BOOTSTRAP_EAST_KV" "$BOOTSTRAP_EAST_RG"
  wait_for_kv_bootstrap_network_ready "$BOOTSTRAP_CANADA_KV" "$BOOTSTRAP_CANADA_RG"

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

load_storage_bootstrap_targets() {
  STORAGE_BOOTSTRAP_EAST_RG="$(tf output -raw eastus2_rg_name 2>/dev/null || tfvar_string eastus2_rg_name)"
  STORAGE_BOOTSTRAP_CANADA_RG="$(tf output -raw canadaeast_rg_name 2>/dev/null || tfvar_string canadaeast_rg_name)"
  STORAGE_BOOTSTRAP_EAST_STORAGE="$(tf output -raw eastus2_storage_name 2>/dev/null || tfvar_string eastus2_storage_name)"
  STORAGE_BOOTSTRAP_CANADA_STORAGE="$(tf output -raw canadaeast_storage_name 2>/dev/null || tfvar_string canadaeast_storage_name)"
  STORAGE_BOOTSTRAP_EAST_DATALAKE="$(tf output -raw eastus2_datalake_storage_name 2>/dev/null || tfvar_string eastus2_datalake_storage_name)"
  STORAGE_BOOTSTRAP_CANADA_DATALAKE="$(tf output -raw canadaeast_datalake_storage_name 2>/dev/null || tfvar_string canadaeast_datalake_storage_name)"
}

wait_for_storage_bootstrap_network_ready() {
  local account_name="$1"
  local resource_group="$2"
  local elapsed=0
  local storage_state=""
  local pna_state=""
  local ip_rule_count=""
  local bootstrap_ip="${BOOTSTRAP_CIDR%%/*}"

  while [[ "$elapsed" -lt "$STORAGE_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS" ]]; do
    storage_state="$(az storage account show --name "$account_name" --resource-group "$resource_group" -o json 2>/dev/null || true)"
    if [[ -n "$storage_state" ]]; then
      pna_state="$(printf '%s' "$storage_state" | jq -r '.publicNetworkAccess // empty')"
      ip_rule_count="$(printf '%s' "$storage_state" | jq -r --arg cidr "$BOOTSTRAP_CIDR" --arg ip "$bootstrap_ip" '[(.networkRuleSet.ipRules // [])[] | (.value // .iPAddressOrRange // .ipAddressOrRange // "") | select(. == $cidr or . == $ip or . == ($ip + "/32") or . == ($ip + "-" + $ip))] | length')"

      if [[ "$pna_state" == "Enabled" && "$ip_rule_count" != "" && "$ip_rule_count" -ge 1 ]]; then
        return
      fi
    fi

    sleep "$STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS"
    elapsed=$((elapsed + STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS))
  done

  echo "Error: temporary storage network bootstrap did not propagate in time for '$account_name'."
  echo "       Last observed state: publicNetworkAccess='${pna_state}', matchingIpRules='${ip_rule_count}'."
  exit 1
}

storage_ip_rule_present() {
  local account_name="$1"
  local resource_group="$2"
  local cidr="$3"
  local ip_only="${cidr%%/*}"
  local rules_json
  local existing_count

  rules_json="$(az storage account network-rule list --account-name "$account_name" --resource-group "$resource_group" -o json 2>/dev/null || true)"
  if [[ -z "$rules_json" ]]; then
    return 1
  fi

  existing_count="$(printf '%s' "$rules_json" | jq -r --arg cidr "$cidr" --arg ip "$ip_only" '[.ipRules[]? | (.value // .iPAddressOrRange // .ipAddressOrRange // "") | select(. == $cidr or . == $ip or . == ($ip + "/32") or . == ($ip + "-" + $ip))] | length')"
  [[ "$existing_count" -ge 1 ]]
}

open_storage_bootstrap_access() {
  detect_bootstrap_cidr
  load_storage_bootstrap_targets

  echo "[INFO] Temporarily enabling storage public access for the current operator IP (${BOOTSTRAP_CIDR}) for Phase 4 filesystem bootstrap..."
  echo "[INFO] This exception is temporary and will be removed before the script completes."

  az storage account update --name "$STORAGE_BOOTSTRAP_EAST_STORAGE" --resource-group "$STORAGE_BOOTSTRAP_EAST_RG" --public-network-access Enabled --default-action Deny >/dev/null
  az storage account update --name "$STORAGE_BOOTSTRAP_CANADA_STORAGE" --resource-group "$STORAGE_BOOTSTRAP_CANADA_RG" --public-network-access Enabled --default-action Deny >/dev/null
  az storage account update --name "$STORAGE_BOOTSTRAP_EAST_DATALAKE" --resource-group "$STORAGE_BOOTSTRAP_EAST_RG" --public-network-access Enabled --default-action Deny >/dev/null
  az storage account update --name "$STORAGE_BOOTSTRAP_CANADA_DATALAKE" --resource-group "$STORAGE_BOOTSTRAP_CANADA_RG" --public-network-access Enabled --default-action Deny >/dev/null

  add_storage_network_rule "$STORAGE_BOOTSTRAP_EAST_STORAGE" "$STORAGE_BOOTSTRAP_EAST_RG" "$BOOTSTRAP_CIDR"
  add_storage_network_rule "$STORAGE_BOOTSTRAP_CANADA_STORAGE" "$STORAGE_BOOTSTRAP_CANADA_RG" "$BOOTSTRAP_CIDR"
  add_storage_network_rule "$STORAGE_BOOTSTRAP_EAST_DATALAKE" "$STORAGE_BOOTSTRAP_EAST_RG" "$BOOTSTRAP_CIDR"
  add_storage_network_rule "$STORAGE_BOOTSTRAP_CANADA_DATALAKE" "$STORAGE_BOOTSTRAP_CANADA_RG" "$BOOTSTRAP_CIDR"

  echo "[INFO] Waiting for temporary storage network access propagation..."
  wait_for_storage_bootstrap_network_ready "$STORAGE_BOOTSTRAP_EAST_STORAGE" "$STORAGE_BOOTSTRAP_EAST_RG"
  wait_for_storage_bootstrap_network_ready "$STORAGE_BOOTSTRAP_CANADA_STORAGE" "$STORAGE_BOOTSTRAP_CANADA_RG"
  wait_for_storage_bootstrap_network_ready "$STORAGE_BOOTSTRAP_EAST_DATALAKE" "$STORAGE_BOOTSTRAP_EAST_RG"
  wait_for_storage_bootstrap_network_ready "$STORAGE_BOOTSTRAP_CANADA_DATALAKE" "$STORAGE_BOOTSTRAP_CANADA_RG"

  sleep "$STORAGE_BOOTSTRAP_POST_READY_SLEEP_SECONDS"

  STORAGE_BOOTSTRAP_OPEN=true
}

wait_for_storage_data_plane_access() {
  local account_name="$1"
  local elapsed=0

  while [[ "$elapsed" -lt "$STORAGE_DATA_PLANE_TIMEOUT_SECONDS" ]]; do
    if az storage fs list --account-name "$account_name" --auth-mode login --only-show-errors >/dev/null 2>&1; then
      return
    fi

    sleep "$STORAGE_DATA_PLANE_POLL_SECONDS"
    elapsed=$((elapsed + STORAGE_DATA_PLANE_POLL_SECONDS))
  done

  echo "Error: storage data-plane access did not propagate in time for account '$account_name'."
  echo "       Ensure public network bootstrap and Storage Blob Data Owner RBAC are effective for the current operator."
  exit 1
}

add_storage_network_rule() {
  local account_name="$1"
  local resource_group="$2"
  local cidr="$3"
  local ip_only="${cidr%%/*}"

  if storage_ip_rule_present "$account_name" "$resource_group" "$cidr"; then
    return
  fi

  if az storage account network-rule add --account-name "$account_name" --resource-group "$resource_group" --ip-address "$ip_only" --only-show-errors >/dev/null 2>&1; then
    return
  fi

  # If add reported an error but rule now exists (duplicate, eventual consistency), continue.
  if storage_ip_rule_present "$account_name" "$resource_group" "$cidr"; then
    return
  fi

  echo "Error: failed to apply temporary storage firewall rule for '$ip_only' on account '$account_name'."
  exit 1
}

remove_storage_network_rule() {
  local account_name="$1"
  local resource_group="$2"
  local cidr="$3"
  local ip_only="${cidr%%/*}"

  az storage account network-rule remove --account-name "$account_name" --resource-group "$resource_group" --ip-address "$ip_only" >/dev/null 2>&1 || true
}

open_storage_operator_data_plane_access() {
  local east_scope canada_scope
  local east_existing canada_existing

  load_storage_bootstrap_targets

  STORAGE_OPERATOR_OBJECT_ID="$(tf output -raw current_operator_object_id 2>/dev/null || true)"
  if [[ -z "$STORAGE_OPERATOR_OBJECT_ID" ]]; then
    echo "Error: unable to resolve current operator object ID from Terraform outputs for temporary storage data-plane access."
    exit 1
  fi

  east_scope="$(az storage account show --name "$STORAGE_BOOTSTRAP_EAST_DATALAKE" --resource-group "$STORAGE_BOOTSTRAP_EAST_RG" --query id -o tsv)"
  canada_scope="$(az storage account show --name "$STORAGE_BOOTSTRAP_CANADA_DATALAKE" --resource-group "$STORAGE_BOOTSTRAP_CANADA_RG" --query id -o tsv)"

  echo "[INFO] Granting temporary Storage Blob Data Owner role to operator for Data Lake filesystem bootstrap..."

  east_existing="$(az role assignment list --scope "$east_scope" --assignee "$STORAGE_OPERATOR_OBJECT_ID" --role "Storage Blob Data Owner" --query "[0].id" -o tsv 2>/dev/null || true)"
  if [[ -z "$east_existing" || "$east_existing" == "null" ]]; then
    STORAGE_OPERATOR_ASSIGNMENT_EAST_ID="$(az role assignment create --assignee-object-id "$STORAGE_OPERATOR_OBJECT_ID" --assignee-principal-type User --role "Storage Blob Data Owner" --scope "$east_scope" --query id -o tsv)"
  fi

  canada_existing="$(az role assignment list --scope "$canada_scope" --assignee "$STORAGE_OPERATOR_OBJECT_ID" --role "Storage Blob Data Owner" --query "[0].id" -o tsv 2>/dev/null || true)"
  if [[ -z "$canada_existing" || "$canada_existing" == "null" ]]; then
    STORAGE_OPERATOR_ASSIGNMENT_CANADA_ID="$(az role assignment create --assignee-object-id "$STORAGE_OPERATOR_OBJECT_ID" --assignee-principal-type User --role "Storage Blob Data Owner" --scope "$canada_scope" --query id -o tsv)"
  fi

  echo "[INFO] Verifying DFS data-plane access before filesystem creation..."
  wait_for_storage_data_plane_access "$STORAGE_BOOTSTRAP_EAST_DATALAKE"
  wait_for_storage_data_plane_access "$STORAGE_BOOTSTRAP_CANADA_DATALAKE"

  STORAGE_OPERATOR_RBAC_OPEN=true
}

restore_storage_operator_data_plane_access() {
  if [[ "$STORAGE_OPERATOR_RBAC_OPEN" != true ]]; then
    return
  fi

  echo "[INFO] Removing temporary operator Storage Blob Data Owner role assignments..."
  if [[ -n "$STORAGE_OPERATOR_ASSIGNMENT_EAST_ID" ]]; then
    az role assignment delete --ids "$STORAGE_OPERATOR_ASSIGNMENT_EAST_ID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$STORAGE_OPERATOR_ASSIGNMENT_CANADA_ID" ]]; then
    az role assignment delete --ids "$STORAGE_OPERATOR_ASSIGNMENT_CANADA_ID" >/dev/null 2>&1 || true
  fi

  STORAGE_OPERATOR_RBAC_OPEN=false
}

restore_storage_lockdown() {
  if [[ "$STORAGE_BOOTSTRAP_OPEN" != true ]]; then
    return
  fi

  load_storage_bootstrap_targets

  echo "[INFO] Restoring storage account public network access to disabled and clearing temporary operator IP rules..."
  remove_storage_network_rule "$STORAGE_BOOTSTRAP_EAST_STORAGE" "$STORAGE_BOOTSTRAP_EAST_RG" "$BOOTSTRAP_CIDR"
  remove_storage_network_rule "$STORAGE_BOOTSTRAP_CANADA_STORAGE" "$STORAGE_BOOTSTRAP_CANADA_RG" "$BOOTSTRAP_CIDR"
  remove_storage_network_rule "$STORAGE_BOOTSTRAP_EAST_DATALAKE" "$STORAGE_BOOTSTRAP_EAST_RG" "$BOOTSTRAP_CIDR"
  remove_storage_network_rule "$STORAGE_BOOTSTRAP_CANADA_DATALAKE" "$STORAGE_BOOTSTRAP_CANADA_RG" "$BOOTSTRAP_CIDR"
  az storage account update --name "$STORAGE_BOOTSTRAP_EAST_STORAGE" --resource-group "$STORAGE_BOOTSTRAP_EAST_RG" --public-network-access Disabled >/dev/null 2>&1 || true
  az storage account update --name "$STORAGE_BOOTSTRAP_CANADA_STORAGE" --resource-group "$STORAGE_BOOTSTRAP_CANADA_RG" --public-network-access Disabled >/dev/null 2>&1 || true
  az storage account update --name "$STORAGE_BOOTSTRAP_EAST_DATALAKE" --resource-group "$STORAGE_BOOTSTRAP_EAST_RG" --public-network-access Disabled >/dev/null 2>&1 || true
  az storage account update --name "$STORAGE_BOOTSTRAP_CANADA_DATALAKE" --resource-group "$STORAGE_BOOTSTRAP_CANADA_RG" --public-network-access Disabled >/dev/null 2>&1 || true

  STORAGE_BOOTSTRAP_OPEN=false
}

destroy_phase4() {
  echo "[INFO] Destroying Phase 4 storage CMK bindings..."
  tf destroy \
    -target=azurerm_storage_account_customer_managed_key.eastus2_storage_cmk_binding \
    -target=azurerm_storage_account_customer_managed_key.eastus2_datalake_cmk_binding \
    -target=azurerm_storage_account_customer_managed_key.canadaeast_storage_cmk_binding \
    -target=azurerm_storage_account_customer_managed_key.canadaeast_datalake_cmk_binding \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true

  echo "[INFO] Destroying Phase 4 storage Key Vault RBAC and propagation wait resources..."
  tf destroy \
    -target=time_sleep.storage_key_vault_rbac_propagation \
    -target=azurerm_role_assignment.eastus2_storage_key_vault_crypto_user \
    -target=azurerm_role_assignment.eastus2_datalake_key_vault_crypto_user \
    -target=azurerm_role_assignment.canadaeast_storage_key_vault_crypto_user \
    -target=azurerm_role_assignment.canadaeast_datalake_key_vault_crypto_user \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true

  echo "[INFO] Destroying Phase 4 storage account modules..."
  tf destroy \
    -target=module.eastus2_storage \
    -target=module.canadaeast_storage \
    -target=module.eastus2_datalake \
    -target=module.canadaeast_datalake \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true

  if [[ "$CLEANUP_ALL" == true ]]; then
    echo "[INFO] Destroying prerequisite Phase 3 resources while retaining Key Vaults and lower-phase infrastructure..."
    "$REPO_ROOT/scripts/test-phase3-cmk.sh" --cleanup-phase -f "$TFVARS_FILE" "${PHASE3_ARGS[@]}"
  fi
}

cleanup() {
  local exit_code="$1"

  if [[ "$STORAGE_OPERATOR_RBAC_OPEN" == true ]]; then
    restore_storage_operator_data_plane_access
  fi

  if [[ "$STORAGE_BOOTSTRAP_OPEN" == true ]]; then
    restore_storage_lockdown
  fi

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

  echo "[INFO] Validation failed or run completed — rolling back Phase 4 deployment..."
  destroy_phase4

  if [[ "$exit_code" -eq 0 ]]; then
    echo "[PASS] Phase 4 test completed and cleanup finished."
  else
    echo "[WARN] Phase 4 test failed; rollback attempted. Review errors above."
  fi
}

trap 'cleanup $?' EXIT

echo "[INFO] Initializing Terraform..."
tf init -upgrade=false >/dev/null

require_phase4_key_vault_prerequisites

if [[ "$CLEANUP_ALL" == true ]]; then
  CLEANUP_PHASE=true
fi

if [[ "$CLEANUP_PHASE" == true ]]; then
  destroy_phase4
  echo "[PASS] Cleanup operation completed."
  exit 0
fi

echo "[INFO] Applying Phase 3 prerequisites via Phase 3 gate script..."
"$REPO_ROOT/scripts/test-phase3-cmk.sh" --keep -f "$TFVARS_FILE" "${PHASE3_ARGS[@]}"

open_key_vault_bootstrap_access

echo "[INFO] Importing any storage accounts that exist in Azure but not in Terraform state..."
import_storage_accounts_if_needed

echo "[INFO] Applying Phase 4 storage accounts and Data Lake filesystems..."
tf apply \
  -target=module.eastus2_storage.azurerm_storage_account.this \
  -target=module.eastus2_storage.azurerm_storage_share.fileshare \
  -target=module.canadaeast_storage.azurerm_storage_account.this \
  -target=module.canadaeast_storage.azurerm_storage_share.fileshare \
  -target=module.eastus2_datalake.azurerm_storage_account.this \
  -target=module.eastus2_datalake.time_sleep.filesystem_propagation_wait \
  -target=module.canadaeast_datalake.azurerm_storage_account.this \
  -target=module.canadaeast_datalake.time_sleep.filesystem_propagation_wait \
  -var-file="$TFVARS_FILE" \
  -var=create_datalake_filesystems=false \
  -var=storage_public_network_access_enabled=true \
  "${TF_APPROVE_ARGS[@]}"

open_storage_bootstrap_access

open_storage_operator_data_plane_access

echo "[INFO] Creating Data Lake filesystems..."
tf apply \
  -target=module.eastus2_datalake \
  -target=module.canadaeast_datalake \
  -var-file="$TFVARS_FILE" \
  -var=create_datalake_filesystems=true \
  -var=storage_public_network_access_enabled=true \
  "${TF_APPROVE_ARGS[@]}"

echo "[INFO] Applying Phase 4 storage Key Vault RBAC and CMK bindings..."
tf apply \
  -target=azurerm_role_assignment.eastus2_storage_key_vault_crypto_user \
  -target=azurerm_role_assignment.eastus2_datalake_key_vault_crypto_user \
  -target=azurerm_role_assignment.canadaeast_storage_key_vault_crypto_user \
  -target=azurerm_role_assignment.canadaeast_datalake_key_vault_crypto_user \
  -target=time_sleep.storage_key_vault_rbac_propagation \
  -target=azurerm_storage_account_customer_managed_key.eastus2_storage_cmk_binding \
  -target=azurerm_storage_account_customer_managed_key.eastus2_datalake_cmk_binding \
  -target=azurerm_storage_account_customer_managed_key.canadaeast_storage_cmk_binding \
  -target=azurerm_storage_account_customer_managed_key.canadaeast_datalake_cmk_binding \
  -var-file="$TFVARS_FILE" \
  -var=storage_public_network_access_enabled=true \
  "${TF_APPROVE_ARGS[@]}"

restore_key_vault_lockdown
restore_storage_operator_data_plane_access
restore_storage_lockdown

echo "[INFO] Reconciling Terraform state for storage public network access after CLI lockdown restore..."
tf apply \
  -refresh=false \
  -target=module.eastus2_storage.azurerm_storage_account.this \
  -target=module.canadaeast_storage.azurerm_storage_account.this \
  -target=module.eastus2_datalake.azurerm_storage_account.this \
  -target=module.canadaeast_datalake.azurerm_storage_account.this \
  -var-file="$TFVARS_FILE" \
  -var=create_datalake_filesystems=true \
  "${TF_APPROVE_ARGS[@]}"

DEPLOYED=true


echo "[INFO] Collecting outputs for validation..."
EAST_RG="$(tf output -raw eastus2_rg_name)"
CANADA_RG="$(tf output -raw canadaeast_rg_name)"
EAST_STORAGE="$(tf output -raw eastus2_storage_name)"
CANADA_STORAGE="$(tf output -raw canadaeast_storage_name)"
EAST_DATALAKE_STORAGE="$(tf output -raw eastus2_datalake_storage_name)"
CANADA_DATALAKE_STORAGE="$(tf output -raw canadaeast_datalake_storage_name)"

validate_storage_hardening() {
  local account_name="$1"
  local resource_group="$2"
  local label="$3"

  local key_source
  local tls_version
  local public_network_access

  key_source="$(az storage account show --name "$account_name" --resource-group "$resource_group" --query encryption.keySource -o tsv)"
  tls_version="$(az storage account show --name "$account_name" --resource-group "$resource_group" --query minimumTlsVersion -o tsv)"
  public_network_access="$(az storage account show --name "$account_name" --resource-group "$resource_group" --query publicNetworkAccess -o tsv)"

  if [[ "$key_source" != "Microsoft.Keyvault" ]]; then
    echo "Error: expected key source Microsoft.Keyvault for $label ('$account_name') but got '$key_source'."
    exit 1
  fi

  if [[ "$tls_version" != "TLS1_2" ]]; then
    echo "Error: expected minimum TLS version TLS1_2 for $label ('$account_name') but got '$tls_version'."
    exit 1
  fi

  if [[ "$public_network_access" != "Disabled" ]]; then
    echo "Error: expected public network access Disabled for $label ('$account_name') but got '$public_network_access'."
    exit 1
  fi
}

echo "[INFO] Validating storage CMK source, TLS policy, and public network access..."
validate_storage_hardening "$EAST_STORAGE" "$EAST_RG" "East US 2 file share storage"
validate_storage_hardening "$CANADA_STORAGE" "$CANADA_RG" "Canada East file share storage"
validate_storage_hardening "$EAST_DATALAKE_STORAGE" "$EAST_RG" "East US 2 Data Lake storage"
validate_storage_hardening "$CANADA_DATALAKE_STORAGE" "$CANADA_RG" "Canada East Data Lake storage"

echo "[PASS] Phase 4 deploy and validation succeeded."
