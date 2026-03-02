#!/bin/bash
#
# Prerequisites:
# 1. Azure CLI installed and authenticated (az login)
# 2. Contributor or Storage Blob Data Contributor access to the storage account
# 3. Storage account and filesystem exist (created by Terraform)
# 4. Bash shell and coreutils (head, base64, rm) available
# 5. Script is executable: chmod +x scripts/populate-source-datalake.sh
#
# Optional:
# - Edit RESOURCE_GROUP, STORAGE_ACCOUNT, FILESYSTEM, or NUM_FILES in the script to match your environment
#
# Usage:
#   ./populate-source-datalake.sh

set -e


# Variables (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-demo-eastus2}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stdldemoeastus2}"
FILESYSTEM="${FILESYSTEM:-fsdleastus2}"
NUM_FILES="${NUM_FILES:-5}"

echo "Using RESOURCE_GROUP=$RESOURCE_GROUP"
echo "Using STORAGE_ACCOUNT=$STORAGE_ACCOUNT"
echo "Using FILESYSTEM=$FILESYSTEM"
echo "Using NUM_FILES=$NUM_FILES"

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
  az storage fs file upload \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$ACCOUNT_KEY" \
    --file-system "$FILESYSTEM" \
    --path "$FILE" \
    --source "$FILE"
  rm "$FILE"
  echo "Uploaded $FILE"
done

echo "Populated $NUM_FILES random files in $FILESYSTEM on $STORAGE_ACCOUNT."
