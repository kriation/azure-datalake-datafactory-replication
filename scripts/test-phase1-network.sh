#!/usr/bin/env bash
# test-phase1-network.sh
# Deploys, validates, and destroys Phase 1 network foundation resources.

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

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --tfvars FILE      Terraform var-file name under terraform/ (default: demo.tfvars)
  -k, --keep             Keep deployed resources (skip destroy)
  --cleanup-phase        Destroy Phase 1 networks only (skip deploy/validate)
  --cleanup-all          Destroy Phase 1 networks and resource groups (implies --cleanup-phase)
  --no-auto-approve      Disable -auto-approve in terraform apply/destroy
  -h, --help             Show this help

Examples:
  ./scripts/test-phase1-network.sh
  ./scripts/test-phase1-network.sh --tfvars demo.tfvars --keep
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

destroy_phase1() {
  echo "[INFO] Destroying Phase 1 network modules..."
  tf destroy -target=module.eastus2_network -target=module.canadaeast_network -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}" || true

  if [[ "$CLEANUP_ALL" == true ]]; then
    echo "[INFO] Destroying Phase 1 resource groups..."
    tf destroy -target=module.eastus2_rg -target=module.canadaeast_rg -var-file="$TFVARS_FILE" "${TF_APPROVE_ARGS[@]}" || true
  fi
}

cleanup() {
  local exit_code="$1"

  if [[ "$KEEP_RESOURCES" == true ]]; then
    echo "[INFO] --keep set, skipping destroy."
    return
  fi

  if [[ "$DEPLOYED" != true ]]; then
    return
  fi

  destroy_phase1

  if [[ "$exit_code" -eq 0 ]]; then
    echo "[PASS] Phase 1 test completed and cleanup finished."
  else
    echo "[WARN] Phase 1 test failed; cleanup attempted."
  fi
}

trap 'cleanup $?' EXIT

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
DEPLOYED=true

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
