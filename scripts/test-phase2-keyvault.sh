#!/usr/bin/env bash
# test-phase2-keyvault.sh
# Deploys and validates Phase 2 Key Vault foundation resources.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
TFVARS_FILE="demo.tfvars"
CLEANUP_ALL=false
AUTO_APPROVE=true
CLEANUP_PHASE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --tfvars FILE      Terraform var-file name under terraform/ (default: demo.tfvars)
  --cleanup-phase        No-op: Key Vaults are permanent once created with purge protection
  --cleanup-all          No-op: Key Vaults and prerequisites are permanent once Phase 2 is applied
  --no-auto-approve      Disable -auto-approve in terraform apply/destroy
  -h, --help             Show this help

Examples:
  ./scripts/test-phase2-keyvault.sh
  ./scripts/test-phase2-keyvault.sh --cleanup-phase
  ./scripts/test-phase2-keyvault.sh --cleanup-all
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--tfvars)
      TFVARS_FILE="$2"
      shift 2
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

for cmd in terraform az jq; do
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

tf() {
  terraform -chdir="$TF_DIR" "$@"
}

cleanup_not_supported() {
  echo "[INFO] Phase 2 cleanup is disabled: purge-protected Key Vaults are permanent once created."
  echo "[INFO] To start fresh, use new Key Vault names in demo.tfvars (the old names remain reserved for the soft-delete retention period)."
}

echo "[INFO] Initializing Terraform..."
tf init -upgrade=false >/dev/null

# --cleanup-all implies --cleanup-phase
if [[ "$CLEANUP_ALL" == true ]]; then
  CLEANUP_PHASE=true
fi

if [[ "$CLEANUP_PHASE" == true ]]; then
  cleanup_not_supported
  exit 0
fi

echo "[INFO] Applying Phase 1 prerequisites (resource groups + network)..."
tf apply -target=module.eastus2_rg -target=module.canadaeast_rg -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"
tf apply -target=module.eastus2_network -target=module.canadaeast_network -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

# Soft-deleted vault guard: detect names that would block re-deployment
check_soft_deleted_vaults() {
  local vault_names=("$@")
  local blocked=false

  for vault_name in "${vault_names[@]}"; do
    if [[ -z "$vault_name" ]]; then continue; fi
    local deleted_location
    deleted_location="$(az keyvault list-deleted --query "[?name=='$vault_name'] | [0].properties.location" -o tsv 2>/dev/null || true)"
    if [[ -n "$deleted_location" && "$deleted_location" != "null" ]]; then
      echo "[ERROR] Key Vault '$vault_name' is soft-deleted and its name is reserved. To release it:"
      echo "          az keyvault purge --name '$vault_name' --location '$deleted_location'"
      blocked=true
    fi
  done

  if [[ "$blocked" == true ]]; then
    echo "[ERROR] Resolve soft-deleted vault(s) above before re-deploying."
    exit 1
  fi
}
EAST_KV_NAME_CHECK="$(tf output -raw eastus2_key_vault_name 2>/dev/null || true)"
CANADA_KV_NAME_CHECK="$(tf output -raw canadaeast_key_vault_name 2>/dev/null || true)"
# Fall back to tfvars values if state is empty (fresh environment)
[[ -z "$EAST_KV_NAME_CHECK" ]] && EAST_KV_NAME_CHECK="$(grep 'eastus2_key_vault_name' "$TFVARS_PATH" | awk -F'"' '{print $2}')"
[[ -z "$CANADA_KV_NAME_CHECK" ]] && CANADA_KV_NAME_CHECK="$(grep 'canadaeast_key_vault_name' "$TFVARS_PATH" | awk -F'"' '{print $2}')"
check_soft_deleted_vaults "$EAST_KV_NAME_CHECK" "$CANADA_KV_NAME_CHECK"

echo "[INFO] Applying Phase 2 key vault modules..."
tf apply -target=module.eastus2_key_vault -target=module.canadaeast_key_vault -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

echo "[INFO] Collecting outputs for validation..."
EAST_RG="$(tf output -raw eastus2_rg_name)"
CANADA_RG="$(tf output -raw canadaeast_rg_name)"
EAST_KV="$(tf output -raw eastus2_key_vault_name)"
CANADA_KV="$(tf output -raw canadaeast_key_vault_name)"
EAST_PE_ID="$(tf output -raw eastus2_key_vault_private_endpoint_id)"
CANADA_PE_ID="$(tf output -raw canadaeast_key_vault_private_endpoint_id)"

extract_name_from_id() {
  local resource_id="$1"
  echo "$resource_id" | awk -F'/' '{print $NF}'
}

EAST_PE_NAME="$(extract_name_from_id "$EAST_PE_ID")"
CANADA_PE_NAME="$(extract_name_from_id "$CANADA_PE_ID")"

echo "[INFO] Validating Key Vault network posture..."
EAST_PUBLIC_ACCESS="$(az keyvault show --name "$EAST_KV" --resource-group "$EAST_RG" --query properties.publicNetworkAccess -o tsv)"
CANADA_PUBLIC_ACCESS="$(az keyvault show --name "$CANADA_KV" --resource-group "$CANADA_RG" --query properties.publicNetworkAccess -o tsv)"

if [[ "$EAST_PUBLIC_ACCESS" != "Disabled" ]]; then
  echo "Error: East US 2 Key Vault public network access expected Disabled but got '$EAST_PUBLIC_ACCESS'."
  exit 1
fi

if [[ "$CANADA_PUBLIC_ACCESS" != "Disabled" ]]; then
  echo "Error: Canada East Key Vault public network access expected Disabled but got '$CANADA_PUBLIC_ACCESS'."
  exit 1
fi

EAST_DEFAULT_ACTION="$(az keyvault show --name "$EAST_KV" --resource-group "$EAST_RG" --query properties.networkAcls.defaultAction -o tsv)"
CANADA_DEFAULT_ACTION="$(az keyvault show --name "$CANADA_KV" --resource-group "$CANADA_RG" --query properties.networkAcls.defaultAction -o tsv)"

if [[ "$EAST_DEFAULT_ACTION" != "Deny" ]]; then
  echo "Error: East US 2 Key Vault network defaultAction expected Deny but got '$EAST_DEFAULT_ACTION'."
  exit 1
fi

if [[ "$CANADA_DEFAULT_ACTION" != "Deny" ]]; then
  echo "Error: Canada East Key Vault network defaultAction expected Deny but got '$CANADA_DEFAULT_ACTION'."
  exit 1
fi

echo "[INFO] Validating Key Vault private endpoint status..."
EAST_PE_PROVISIONING="$(az network private-endpoint show --ids "$EAST_PE_ID" --query provisioningState -o tsv)"
CANADA_PE_PROVISIONING="$(az network private-endpoint show --ids "$CANADA_PE_ID" --query provisioningState -o tsv)"

if [[ "$EAST_PE_PROVISIONING" != "Succeeded" ]]; then
  echo "Error: East US 2 Key Vault private endpoint provisioning state expected Succeeded but got '$EAST_PE_PROVISIONING'."
  exit 1
fi

if [[ "$CANADA_PE_PROVISIONING" != "Succeeded" ]]; then
  echo "Error: Canada East Key Vault private endpoint provisioning state expected Succeeded but got '$CANADA_PE_PROVISIONING'."
  exit 1
fi

EAST_PE_LINK_STATUS="$(az network private-endpoint show --ids "$EAST_PE_ID" --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status' -o tsv)"
CANADA_PE_LINK_STATUS="$(az network private-endpoint show --ids "$CANADA_PE_ID" --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status' -o tsv)"

if [[ "$EAST_PE_LINK_STATUS" != "Approved" ]]; then
  echo "Error: East US 2 Key Vault private endpoint connection status expected Approved but got '$EAST_PE_LINK_STATUS'."
  exit 1
fi

if [[ "$CANADA_PE_LINK_STATUS" != "Approved" ]]; then
  echo "Error: Canada East Key Vault private endpoint connection status expected Approved but got '$CANADA_PE_LINK_STATUS'."
  exit 1
fi

echo "[INFO] Validating private DNS zone group binding..."
az network private-endpoint dns-zone-group show --name keyvault-zone-group --endpoint-name "$EAST_PE_NAME" --resource-group "$EAST_RG" --query "privateDnsZoneConfigs[?contains(privateDnsZoneId, 'privatelink.vaultcore.azure.net')]" -o json | jq -e 'length > 0' >/dev/null
az network private-endpoint dns-zone-group show --name keyvault-zone-group --endpoint-name "$CANADA_PE_NAME" --resource-group "$CANADA_RG" --query "privateDnsZoneConfigs[?contains(privateDnsZoneId, 'privatelink.vaultcore.azure.net')]" -o json | jq -e 'length > 0' >/dev/null

echo "[PASS] Phase 2 deploy and validation succeeded."
