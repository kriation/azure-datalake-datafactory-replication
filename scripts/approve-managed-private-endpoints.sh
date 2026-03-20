#!/usr/bin/env bash
#
# Approve all pending managed private endpoint connections for fileshare storage accounts.
#
# Phase 8 helper: Approves private endpoint connections created by Data Factory managed VNet IR
# so that fileshare linked services can route through the managed integration runtime.
#
# Prerequisites:
# 1. Azure CLI installed and authenticated (az login)
# 2. Contributor or Storage Account Contributor access to both fileshare storage accounts
# 3. Script is executable: chmod +x scripts/approve-managed-private-endpoints.sh
#
# Usage:
#   ./approve-managed-private-endpoints.sh
#   ./approve-managed-private-endpoints.sh -g rg-demo-eastus2 -a stdemoeastus2 -r2 rg-demo-canadaeast -s2 stdemocanadaeast

set -euo pipefail

# Default resource groups and storage accounts
SOURCE_RG="rg-demo-eastus2"
SOURCE_STORAGE="stdemoeastus2"
DEST_RG="rg-demo-canadaeast"
DEST_STORAGE="stdemocanadaeast"

# Usage info
usage() {
  echo "Usage: $0 [-g SOURCE_RG] [-a SOURCE_STORAGE] [-r2 DEST_RG] [-s2 DEST_STORAGE]"
  echo "  -g SOURCE_RG           Source resource group (default: rg-demo-eastus2)"
  echo "  -a SOURCE_STORAGE      Source storage account (default: stdemoeastus2)"
  echo "  -r2 DEST_RG            Destination resource group (default: rg-demo-canadaeast)"
  echo "  -s2 DEST_STORAGE       Destination storage account (default: stdemocanadaeast)"
  exit 1
}

# Parse arguments
while getopts "g:a:r:s:h" opt; do
  case $opt in
    g) SOURCE_RG="$OPTARG" ;;
    a) SOURCE_STORAGE="$OPTARG" ;;
    r) DEST_RG="$OPTARG" ;;
    s) DEST_STORAGE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Verify Azure CLI is authenticated
if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not authenticated. Run 'az login' first."
  exit 1
fi

approve_pending_endpoints() {
  local storage_account="$1"
  local resource_group="$2"
  local account_label="$3"

  echo "[INFO] Checking for pending private endpoint connections on $account_label ($storage_account)..."

  # Get all private endpoint connections
  local connections
  connections=$(az network private-endpoint-connection list \
    --name "$storage_account" \
    --resource-group "$resource_group" \
    --type Microsoft.Storage/storageAccounts \
    -o json 2>/dev/null || echo "[]")

  if [[ "$connections" == "[]" ]]; then
    echo "[INFO] No private endpoint connections found on $account_label."
    return
  fi

  # Filter for pending connections
  local pending_count
  pending_count=$(printf '%s' "$connections" | jq '[.[] | select(.properties.privateLinkServiceConnectionState.status == "Pending")] | length')

  if [[ "$pending_count" -eq 0 ]]; then
    echo "[INFO] No pending private endpoint connections on $account_label."
    return
  fi

  echo "[INFO] Found $pending_count pending connection(s) on $account_label. Approving..."

  # Approve each pending connection
  printf '%s' "$connections" | jq -r '.[] | select(.properties.privateLinkServiceConnectionState.status == "Pending") | .id' | while read -r connection_id; do
    local connection_name
    connection_name=$(printf '%s' "$connection_id" | rev | cut -d'/' -f1 | rev)
    
    echo "[INFO] Approving private endpoint connection: $connection_name"
    
    az network private-endpoint-connection approve \
      --id "$connection_id" \
      --description "Approved by Phase 8 automation" \
      >/dev/null 2>&1 || {
        echo "[WARN] Failed to approve $connection_name. It may already be approved or in transition."
      }
  done

  # Verify approvals
  echo "[INFO] Verifying approval status on $account_label..."
  local updated_connections
  updated_connections=$(az network private-endpoint-connection list \
    --name "$storage_account" \
    --resource-group "$resource_group" \
    --type Microsoft.Storage/storageAccounts \
    -o json)

  local approved_count
  approved_count=$(printf '%s' "$updated_connections" | jq '[.[] | select(.properties.privateLinkServiceConnectionState.status == "Approved")] | length')

  local still_pending
  still_pending=$(printf '%s' "$updated_connections" | jq '[.[] | select(.properties.privateLinkServiceConnectionState.status == "Pending")] | length')

  echo "[INFO] $account_label approval summary: Approved=$approved_count, Pending=$still_pending"
}

echo "=========================================="
echo "Phase 8: Approve Managed Private Endpoints"
echo "=========================================="
echo ""

# Approve both storage accounts
approve_pending_endpoints "$SOURCE_STORAGE" "$SOURCE_RG" "Source fileshare (East US 2)"
echo ""
approve_pending_endpoints "$DEST_STORAGE" "$DEST_RG" "Destination fileshare (Canada East)"

echo ""
echo "[INFO] Private endpoint approval complete."
echo "[INFO] Run './scripts/validate-adf-health.sh --pipelines copyfilesharepipeline' to verify fileshare replication."
