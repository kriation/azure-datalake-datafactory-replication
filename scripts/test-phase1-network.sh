#!/usr/bin/env bash
# test-phase1-network.sh
# Deploys, validates, and destroys Phase 1 network foundation resources.

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
  --cleanup-phase        Destroy Phase 1 networks only (skip deploy/validate; blocked if Key Vaults exist)
  --cleanup-all          Destroy Phase 1 networks and resource groups (blocked if Key Vaults exist)
  --no-auto-approve      Disable -auto-approve in terraform apply/destroy
  -h, --help             Show this help

Examples:
  ./scripts/test-phase1-network.sh
  ./scripts/test-phase1-network.sh --cleanup-phase
  ./scripts/test-phase1-network.sh --cleanup-all
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

phase2_key_vaults_exist() {
  local east_kv_name canada_kv_name

  east_kv_name="$(grep 'eastus2_key_vault_name' "$TFVARS_PATH" | awk -F'"' '{print $2}')"
  canada_kv_name="$(grep 'canadaeast_key_vault_name' "$TFVARS_PATH" | awk -F'"' '{print $2}')"

  if [[ -n "$east_kv_name" ]] && az keyvault show --name "$east_kv_name" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$canada_kv_name" ]] && az keyvault show --name "$canada_kv_name" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

destroy_phase1() {
  if phase2_key_vaults_exist; then
    echo "[WARN] Phase 1 cleanup is blocked: retained Key Vaults exist in this environment."
    echo "       Teardown here would risk cascading into Key Vault deletion via resource group removal."
    echo "       To proceed, first purge the soft-deleted Key Vaults manually, then re-run."
    return
  fi

  echo "[INFO] Destroying Phase 1 network modules..."
  tf destroy -target=module.eastus2_network -target=module.canadaeast_network -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}" || true

  if [[ "$CLEANUP_ALL" == true ]]; then
    echo "[INFO] Destroying Phase 1 resource groups..."
    tf destroy -target=module.eastus2_rg -target=module.canadaeast_rg -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}" || true
  fi
}

echo "[INFO] Initializing Terraform..."
tf init -upgrade=false >/dev/null

# --cleanup-all implies --cleanup-phase
if [[ "$CLEANUP_ALL" == true ]]; then
  CLEANUP_PHASE=true
fi

if [[ "$CLEANUP_PHASE" == true ]]; then
  destroy_phase1
  echo "[PASS] Cleanup operation completed."
  exit 0
fi

echo "[INFO] Applying resource groups (Phase 1 sequence A)..."
tf apply -target=module.eastus2_rg -target=module.canadaeast_rg -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

echo "[INFO] Applying regional networking (Phase 1 sequence B)..."
tf apply -target=module.eastus2_network -target=module.canadaeast_network -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}"

echo "[INFO] Collecting Terraform outputs for validation..."
EAST_RG="$(tf output -raw eastus2_rg_name)"
CANADA_RG="$(tf output -raw canadaeast_rg_name)"
EAST_VNET="$(tf output -raw eastus2_vnet_name)"
CANADA_VNET="$(tf output -raw canadaeast_vnet_name)"
EAST_SUBNET_ID="$(tf output -raw eastus2_private_endpoint_subnet_id)"
CANADA_SUBNET_ID="$(tf output -raw canadaeast_private_endpoint_subnet_id)"
EAST_ZONES_JSON="$(tf output -json eastus2_private_dns_zone_names)"
CANADA_ZONES_JSON="$(tf output -json canadaeast_private_dns_zone_names)"

extract_subnet_name() {
  local subnet_id="$1"
  echo "$subnet_id" | awk -F'/' '{print $NF}'
}

EAST_SUBNET_NAME="$(extract_subnet_name "$EAST_SUBNET_ID")"
CANADA_SUBNET_NAME="$(extract_subnet_name "$CANADA_SUBNET_ID")"

zone_link_name() {
  local vnet_name="$1"
  local zone_name="$2"
  local zone_slug="${zone_name//./-}"
  echo "${vnet_name}-${zone_slug}-link"
}

echo "[INFO] Validating VNets and subnet policy..."
az network vnet show --resource-group "$EAST_RG" --name "$EAST_VNET" --only-show-errors >/dev/null
az network vnet show --resource-group "$CANADA_RG" --name "$CANADA_VNET" --only-show-errors >/dev/null

EAST_POLICY="$(az network vnet subnet show --resource-group "$EAST_RG" --vnet-name "$EAST_VNET" --name "$EAST_SUBNET_NAME" --query privateEndpointNetworkPolicies -o tsv)"
CANADA_POLICY="$(az network vnet subnet show --resource-group "$CANADA_RG" --vnet-name "$CANADA_VNET" --name "$CANADA_SUBNET_NAME" --query privateEndpointNetworkPolicies -o tsv)"

if [[ "$EAST_POLICY" != "Disabled" ]]; then
  echo "Error: East US 2 subnet private endpoint policies expected 'Disabled' but got '$EAST_POLICY'."
  exit 1
fi

if [[ "$CANADA_POLICY" != "Disabled" ]]; then
  echo "Error: Canada East subnet private endpoint policies expected 'Disabled' but got '$CANADA_POLICY'."
  exit 1
fi

echo "[INFO] Validating private DNS zones and links..."
while IFS= read -r zone; do
  [[ -z "$zone" ]] && continue
  az network private-dns zone show --resource-group "$EAST_RG" --name "$zone" --only-show-errors >/dev/null
  az network private-dns link vnet show --resource-group "$EAST_RG" --zone-name "$zone" --name "$(zone_link_name "$EAST_VNET" "$zone")" --only-show-errors >/dev/null
done < <(echo "$EAST_ZONES_JSON" | jq -r '.[]')

while IFS= read -r zone; do
  [[ -z "$zone" ]] && continue
  az network private-dns zone show --resource-group "$CANADA_RG" --name "$zone" --only-show-errors >/dev/null
  az network private-dns link vnet show --resource-group "$CANADA_RG" --zone-name "$zone" --name "$(zone_link_name "$CANADA_VNET" "$zone")" --only-show-errors >/dev/null
done < <(echo "$CANADA_ZONES_JSON" | jq -r '.[]')

echo "[PASS] Phase 1 deploy and validation succeeded."
