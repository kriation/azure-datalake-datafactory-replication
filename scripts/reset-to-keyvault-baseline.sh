#!/usr/bin/env bash
# reset-to-keyvault-baseline.sh
# Purges all resources except the two resource groups and two empty Key Vaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
TFVARS_FILE="demo.tfvars"
AUTO_APPROVE=true
DRY_RUN=false

tfvar_string() {
  local variable_name="$1"
  local line

  line="$(grep -E "^[[:space:]]*${variable_name}[[:space:]]*=" "$TFVARS_PATH" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi

  echo "$line" | awk -F'"' '{print $2}'
}

tf_output_or_tfvar() {
  local output_name="$1"
  local tfvar_name="$2"
  local value

  value="$(tf output -raw "$output_name" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    echo "$value"
    return
  fi

  tfvar_string "$tfvar_name"
}

current_principal_object_id() {
  local oid=""

  oid="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$oid" && "$oid" != "null" ]]; then
    echo "$oid"
    return
  fi

  local account_user
  account_user="$(az account show --query user.name -o tsv 2>/dev/null || true)"
  if [[ -n "$account_user" ]]; then
    oid="$(az ad sp show --id "$account_user" --query id -o tsv 2>/dev/null || true)"
    if [[ -n "$oid" && "$oid" != "null" ]]; then
      echo "$oid"
      return
    fi
  fi

  echo ""
}

has_role_on_scope() {
  local scope="$1"
  local principal_id="$2"
  local role_name="$3"
  local count

  count="$(az role assignment list --scope "$scope" --assignee-object-id "$principal_id" --include-inherited --query "[?roleDefinitionName=='${role_name}'] | length(@)" -o tsv 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -gt 0 ]]
}

preflight_permissions() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[INFO] DRY RUN: skipping RBAC preflight checks."
    return 0
  fi

  local principal_id subscription_id east_rg canada_rg east_kv canada_kv
  local east_rg_scope canada_rg_scope east_kv_scope canada_kv_scope

  principal_id="$(current_principal_object_id)"
  if [[ -z "$principal_id" ]]; then
    echo "Error: unable to resolve current principal object ID for RBAC preflight checks."
    echo "       Ensure Azure CLI login context is valid and retry."
    exit 1
  fi

  subscription_id="$(az account show --query id -o tsv)"
  east_rg="$(tf_output_or_tfvar eastus2_rg_name eastus2_rg_name)"
  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name)"
  east_kv="$(tf_output_or_tfvar eastus2_key_vault_name eastus2_key_vault_name)"
  canada_kv="$(tf_output_or_tfvar canadaeast_key_vault_name canadaeast_key_vault_name)"

  east_rg_scope="/subscriptions/${subscription_id}/resourceGroups/${east_rg}"
  canada_rg_scope="/subscriptions/${subscription_id}/resourceGroups/${canada_rg}"
  east_kv_scope="${east_rg_scope}/providers/Microsoft.KeyVault/vaults/${east_kv}"
  canada_kv_scope="${canada_rg_scope}/providers/Microsoft.KeyVault/vaults/${canada_kv}"

  if ! has_role_on_scope "$east_rg_scope" "$principal_id" "Owner" && ! has_role_on_scope "$east_rg_scope" "$principal_id" "Contributor"; then
    echo "Error: current principal lacks Owner/Contributor on ${east_rg_scope}."
    echo "       This reset requires write/delete permissions at RG scope."
    exit 1
  fi

  if ! has_role_on_scope "$canada_rg_scope" "$principal_id" "Owner" && ! has_role_on_scope "$canada_rg_scope" "$principal_id" "Contributor"; then
    echo "Error: current principal lacks Owner/Contributor on ${canada_rg_scope}."
    echo "       This reset requires write/delete permissions at RG scope."
    exit 1
  fi

  if ! has_role_on_scope "$east_kv_scope" "$principal_id" "Key Vault Administrator"; then
    echo "Error: current principal lacks Key Vault Administrator on ${east_kv_scope}."
    echo "       This reset requires data-plane admin to delete keys/secrets and update network ACLs."
    exit 1
  fi

  if ! has_role_on_scope "$canada_kv_scope" "$principal_id" "Key Vault Administrator"; then
    echo "Error: current principal lacks Key Vault Administrator on ${canada_kv_scope}."
    echo "       This reset requires data-plane admin to delete keys/secrets and update network ACLs."
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --tfvars FILE      Terraform var-file name under terraform/ (default: demo.tfvars)
  --no-auto-approve      Disable -auto-approve in terraform destroy calls
  --dry-run              Print actions without executing
  -h, --help             Show this help

What this keeps:
  - Resource groups
  - Regional Key Vaults (empty)

What this removes:
  - Phase 3 CMKs and related RBAC/data-factory-identity resources
  - Phase 4 storage + datalake resources and storage CMK bindings
  - Phase 5/6 ADF resources, ADF CMK binding, ADF storage RBAC, and ADF KV secrets
  - Key Vault private endpoints and Phase 1 network resources (VNets/subnets/private DNS)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--tfvars)
      TFVARS_FILE="$2"
      shift 2
      ;;
    --no-auto-approve)
      AUTO_APPROVE=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
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

for cmd in terraform az; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not authenticated. Run 'az login' first."
  exit 1
fi

TF_APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" == true ]]; then
  TF_APPROVE_ARGS+=("-auto-approve")
fi

PHASE4_ARGS=("--cleanup-all" "-f" "$TFVARS_FILE")
if [[ "$AUTO_APPROVE" == false ]]; then
  PHASE4_ARGS+=("--no-auto-approve")
fi

tf() {
  terraform -chdir="$TF_DIR" "$@"
}

destroy_phase56() {
  echo "[INFO] Destroying Phase 5/6 resources (ADF + ADF CMK + KV secrets + ADF storage RBAC)..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] terraform -chdir=$TF_DIR destroy -refresh=false ... -var-file=$TFVARS_FILE"
    return 0
  fi

  tf destroy \
    -refresh=false \
    -target=module.data_factory \
    -target=azurerm_data_factory_customer_managed_key.canadaeast_data_factory_cmk_binding \
    -target=azurerm_key_vault_secret.adf_source_fileshare_connection_string \
    -target=azurerm_key_vault_secret.adf_dest_fileshare_connection_string \
    -target=azurerm_role_assignment.adf_to_eastus2_fileshare \
    -target=azurerm_role_assignment.adf_to_canadaeast_fileshare \
    -target=azurerm_role_assignment.adf_to_eastus2_datalake \
    -target=azurerm_role_assignment.adf_to_canadaeast_datalake \
    -target=azurerm_role_assignment.canadaeast_data_factory_key_vault_secrets_user \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true
}

destroy_phase4_and_phase3() {
  echo "[INFO] Destroying Phase 4 and Phase 3 while retaining Key Vaults and lower-phase prerequisites..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] $SCRIPT_DIR/test-phase4-storage-cmk-tls.sh ${PHASE4_ARGS[*]}"
    return 0
  fi

  "$SCRIPT_DIR/test-phase4-storage-cmk-tls.sh" "${PHASE4_ARGS[@]}"
}

destroy_kv_private_endpoints_and_network() {
  echo "[INFO] Destroying Key Vault private endpoints and network foundation (keeping Key Vaults + RGs)..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] terraform -chdir=$TF_DIR destroy -refresh=false -target=module.eastus2_key_vault.azurerm_private_endpoint.this -target=module.canadaeast_key_vault.azurerm_private_endpoint.this -target=module.eastus2_network -target=module.canadaeast_network -var-file=$TFVARS_FILE"
    return 0
  fi

  tf destroy \
    -refresh=false \
    -target=module.eastus2_key_vault.azurerm_private_endpoint.this \
    -target=module.canadaeast_key_vault.azurerm_private_endpoint.this \
    -target=module.eastus2_network \
    -target=module.canadaeast_network \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}" || true
}

echo "[INFO] Initializing Terraform..."
if [[ "$DRY_RUN" == false ]]; then
  tf init -upgrade=false >/dev/null
fi

echo "[INFO] Running RBAC preflight checks..."
preflight_permissions

destroy_phase56
destroy_phase4_and_phase3
destroy_kv_private_endpoints_and_network

echo "[PASS] Purge complete. Only resource groups and empty Key Vaults are retained."
