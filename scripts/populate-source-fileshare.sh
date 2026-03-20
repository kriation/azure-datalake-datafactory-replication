#!/usr/bin/env bash
#
# Prerequisites:
# 1. Azure CLI installed and authenticated (az login)
# 2. Contributor or Storage File Data SMB Share Elevated Contributor access to the storage account
# 3. Storage account and file share (fileshare) exist (created by Terraform)
# 4. Bash shell and coreutils (head, base64, rm) available
# 5. Script is executable: chmod +x scripts/populate-source-fileshare.sh
#
# Note: If the storage account has public network access disabled (Phase 4 lockdown),
# this script temporarily enables access from the current operator IP and restores
# lockdown on exit.
#
# Optional:
# - Edit RESOURCE_GROUP, STORAGE_ACCOUNT, FILE_SHARE, or NUM_FILES in the script to match your environment
#
# Usage:
#   ./populate-source-fileshare.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/storage-network-access.sh
source "$SCRIPT_DIR/lib/storage-network-access.sh"


# Variables (can be overridden by arguments)
RESOURCE_GROUP="rg-demo-eastus2"
STORAGE_ACCOUNT="stdemoeastus2"
FILE_SHARE="fileshare"
NUM_FILES=5
FILE_SIZE="1K"  # Default file size (1K = 1024 bytes)

# Usage info
usage() {
  echo "Usage: $0 [-n NUM_FILES] [-s FILE_SIZE] [-g RESOURCE_GROUP] [-a STORAGE_ACCOUNT] [-f FILE_SHARE]"
  echo "  -n NUM_FILES        Number of files to create (default: 5)"
  echo "  -s FILE_SIZE        Size of each file (e.g., 1K, 10M, 1G; default: 1K)"
  echo "  -g RESOURCE_GROUP   Azure resource group (default: rg-demo-eastus2)"
  echo "  -a STORAGE_ACCOUNT  Azure storage account (default: stdemoeastus2)"
  echo "  -f FILE_SHARE       Azure file share name (default: fileshare)"
  exit 1
}

# Parse arguments
while getopts "n:s:g:a:f:h" opt; do
  case $opt in
    n) NUM_FILES="$OPTARG" ;;
    s) FILE_SIZE="$OPTARG" ;;
    g) RESOURCE_GROUP="$OPTARG" ;;
    a) STORAGE_ACCOUNT="$OPTARG" ;;
    f) FILE_SHARE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Temporarily open storage network access from the current operator IP.
detect_bootstrap_cidr
open_storage_account_access "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"
trap 'close_all_storage_access' EXIT

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query '[0].value' -o tsv)


# Verify the file service data plane is accepting requests before uploading.
wait_for_storage_account_data_plane "file" "$STORAGE_ACCOUNT" "$ACCOUNT_KEY"

# Create random files and upload
for i in $(seq 1 $NUM_FILES); do
  RAND_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  FILE="randomfile_${i}_${RAND_SUFFIX}.bin"
  head -c "$FILE_SIZE" </dev/urandom > "$FILE"
  az storage file upload \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --share-name "$FILE_SHARE" \
    --source "$FILE"
  rm "$FILE"
  echo "Uploaded $FILE ($FILE_SIZE)"
done

echo "Populated $NUM_FILES random files in $FILE_SHARE on $STORAGE_ACCOUNT."