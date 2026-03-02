#!/bin/bash
#
# Prerequisites:
# 1. Azure CLI installed and authenticated (az login)
# 2. Contributor or Storage File Data SMB Share Elevated Contributor access to the storage account
# 3. Storage account and file share (fileshare) exist (created by Terraform)
# 4. Bash shell and coreutils (head, base64, rm) available
# 5. Script is executable: chmod +x scripts/populate-source-fileshare.sh
#
# Optional:
# - Edit RESOURCE_GROUP, STORAGE_ACCOUNT, FILE_SHARE, or NUM_FILES in the script to match your environment
#
# Usage:
#   ./populate-source-fileshare.sh

set -e

# Variables (edit as needed or pass as arguments)
RESOURCE_GROUP="rg-demo-eastus2"
STORAGE_ACCOUNT="stdemoeastus2"
FILE_SHARE="fileshare"
NUM_FILES=5

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query '[0].value' -o tsv)

# Create random files and upload
for i in $(seq 1 $NUM_FILES); do
  RAND_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  FILE="randomfile_${i}_${RAND_SUFFIX}.txt"
  head -c 1024 </dev/urandom | base64 > "$FILE"
  az storage file upload \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --share-name "$FILE_SHARE" \
    --source "$FILE"
  rm "$FILE"
  echo "Uploaded $FILE"
done

echo "Populated $NUM_FILES random files in $FILE_SHARE on $STORAGE_ACCOUNT."