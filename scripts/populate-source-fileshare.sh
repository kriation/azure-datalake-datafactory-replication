#!/usr/bin/env bash
#
# Prerequisites:
# 1. Azure CLI installed and authenticated (az login)
# 2. Contributor or Storage File Data SMB Share Elevated Contributor access to the storage account
# 3. Key Vault Secrets User (or equivalent) access to the Canada East Key Vault
# 4. Storage account and file share (fileshare) exist (created by Terraform)
# 5. Bash shell and coreutils (head, base64, rm) available
# 6. Script is executable: chmod +x scripts/populate-source-fileshare.sh
#
# Note: If the storage account has public network access disabled (Phase 4 lockdown),
# this script temporarily enables access from the current operator IP and restores
# lockdown on exit.
#
# Optional:
# - Edit RESOURCE_GROUP, STORAGE_ACCOUNT, FILE_SHARE, KEY_VAULT_NAME, or SOURCE_SECRET_NAME in the script to match your environment
#
# Usage:
#   ./populate-source-fileshare.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/storage-network-access.sh
source "$SCRIPT_DIR/lib/storage-network-access.sh"
# shellcheck source=lib/keyvault-network-access.sh
source "$SCRIPT_DIR/lib/keyvault-network-access.sh"


# Variables (can be overridden by arguments)
RESOURCE_GROUP="rg-demo-eastus2"
STORAGE_ACCOUNT="stdemoeastus2"
FILE_SHARE="fileshare"
KEY_VAULT_NAME="kvdemocanadaeast"
SOURCE_SECRET_NAME="adf-source-fileshare-connection-string"
NUM_FILES=5
FILE_SIZE="1K"  # Default file size (1K = 1024 bytes)

# Usage info
usage() {
  echo "Usage: $0 [-n NUM_FILES] [-s FILE_SIZE] [-g RESOURCE_GROUP] [-a STORAGE_ACCOUNT] [-f FILE_SHARE] [-k KEY_VAULT_NAME] [-x SOURCE_SECRET_NAME]"
  echo "  -n NUM_FILES        Number of files to create (default: 5)"
  echo "  -s FILE_SIZE        Size of each file (e.g., 1K, 10M, 1G; default: 1K)"
  echo "  -g RESOURCE_GROUP   Azure resource group (default: rg-demo-eastus2)"
  echo "  -a STORAGE_ACCOUNT  Azure storage account (default: stdemoeastus2)"
  echo "  -f FILE_SHARE       Azure file share name (default: fileshare)"
  echo "  -k KEY_VAULT_NAME   Canada East Key Vault name (default: kvdemocanadaeast)"
  echo "  -x SOURCE_SECRET_NAME  Key Vault secret name for source file share connection string"
  exit 1
}

# Parse arguments
while getopts "n:s:g:a:f:k:x:h" opt; do
  case $opt in
    n) NUM_FILES="$OPTARG" ;;
    s) FILE_SIZE="$OPTARG" ;;
    g) RESOURCE_GROUP="$OPTARG" ;;
    a) STORAGE_ACCOUNT="$OPTARG" ;;
    f) FILE_SHARE="$OPTARG" ;;
    k) KEY_VAULT_NAME="$OPTARG" ;;
    x) SOURCE_SECRET_NAME="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

wait_for_file_data_plane_with_connection_string() {
  local connection_string="$1"
  local timeout="${2:-120}"
  local elapsed=0

  while (( elapsed < timeout )); do
    if az storage share list --connection-string "$connection_string" -o none >/dev/null 2>&1; then
      return
    fi

    echo "[INFO] Waiting for '${STORAGE_ACCOUNT}' (file) data plane to become accessible (${elapsed}/${timeout}s)..."
    sleep 10
    elapsed=$((elapsed + 10))
  done

  echo "Error: storage data plane for '${STORAGE_ACCOUNT}' (file) did not become accessible within ${timeout} seconds."
  exit 1
}

# Temporarily open storage network access from the current operator IP.
detect_bootstrap_cidr
trap 'close_all_storage_access; close_all_key_vault_access' EXIT
open_key_vault_access "$KEY_VAULT_NAME"
open_storage_account_access "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"

# Read source file-share connection string from Key Vault.
SOURCE_CONNECTION_STRING="$(az keyvault secret show \
  --vault-name "$KEY_VAULT_NAME" \
  --name "$SOURCE_SECRET_NAME" \
  --query value -o tsv)"

if [[ -z "$SOURCE_CONNECTION_STRING" ]]; then
  echo "Error: secret '${SOURCE_SECRET_NAME}' in Key Vault '${KEY_VAULT_NAME}' is empty or unreadable."
  exit 1
fi


# Verify the file service data plane is accepting requests before uploading.
wait_for_file_data_plane_with_connection_string "$SOURCE_CONNECTION_STRING"

# Create random files and upload
for i in $(seq 1 $NUM_FILES); do
  RAND_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  FILE="randomfile_${i}_${RAND_SUFFIX}.bin"
  head -c "$FILE_SIZE" </dev/urandom > "$FILE"
  az storage file upload \
    --connection-string "$SOURCE_CONNECTION_STRING" \
    --share-name "$FILE_SHARE" \
    --path "$FILE" \
    --source "$FILE"
  rm "$FILE"
  echo "Uploaded $FILE ($FILE_SIZE)"
done

echo "Populated $NUM_FILES random files in $FILE_SHARE on $STORAGE_ACCOUNT."