#!/bin/bash
#
# measure-replication-time.sh
# Measures replication time from source to destination for Azure File Share or Data Lake files.
#
# Usage:
#   ./measure-replication-time.sh -t <type> -f <filename> [options]
#
# Options:
#   -t TYPE            Type: fileshare or datalake (required)
#   -f FILENAME        Name of the file to check (required)
#   -s SOURCE_ACCOUNT  Source storage account name
#   -d DEST_ACCOUNT    Destination storage account name
#   -g SOURCE_RG       Source resource group
#   -h DEST_RG         Destination resource group
#   -S SOURCE_SHARE    Source file share or filesystem
#   -D DEST_SHARE      Destination file share or filesystem
#   -y                 Polling interval in seconds (default: 10)
#   -m                 Max wait time in seconds (default: 1800)
#
# Example:
#   ./measure-replication-time.sh -t fileshare -f randomfile_1_xxxxxxxx.bin \
#     -s stdemoeastus2 -d stdemoeastcanada -g rg-demo-eastus2 -h rg-demo-canadaeast \
#     -S fileshare -D fileshare --interval 10 --max-wait 1800

set -e
# set -x  # Uncomment for bash tracing

# Defaults
POLL_INTERVAL=10
MAX_WAIT=1800


DEBUG=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -t) TYPE="$2"; shift 2;;
    -f) FILENAME="$2"; shift 2;;
    -s) SOURCE_ACCOUNT="$2"; shift 2;;
    -d) DEST_ACCOUNT="$2"; shift 2;;
    -g) SOURCE_RG="$2"; shift 2;;
    -h) DEST_RG="$2"; shift 2;;
    -S) SOURCE_SHARE="$2"; shift 2;;
    -D) DEST_SHARE="$2"; shift 2;;
    --interval|-y) POLL_INTERVAL="$2"; shift 2;;
    --max-wait|-m) MAX_WAIT="$2"; shift 2;;
    --debug) DEBUG=1; shift 1;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done

if [[ -z "$TYPE" || -z "$FILENAME" ]]; then
  echo "Type (-t) and filename (-f) are required."
  exit 1
fi

# Get source and destination account keys
if [[ $DEBUG -eq 1 ]]; then
  echo "[DEBUG] az storage account keys list --resource-group $SOURCE_RG --account-name $SOURCE_ACCOUNT --query '[0].value' -o tsv"
fi
SOURCE_KEY=$(az storage account keys list --resource-group "$SOURCE_RG" --account-name "$SOURCE_ACCOUNT" --query '[0].value' -o tsv 2>&1)
if [[ $? -ne 0 ]]; then echo "[ERROR] $SOURCE_KEY"; exit 1; fi
if [[ $DEBUG -eq 1 ]]; then
  echo "[DEBUG] SOURCE_KEY (first 8 chars): ${SOURCE_KEY:0:8}..."
  echo "[TRACE] Got source key, proceeding to destination key."
  echo "[DEBUG] az storage account keys list --resource-group $DEST_RG --account-name $DEST_ACCOUNT --query '[0].value' -o tsv"
fi
DEST_KEY=$(az storage account keys list --resource-group "$DEST_RG" --account-name "$DEST_ACCOUNT" --query '[0].value' -o tsv 2>&1)
if [[ $? -ne 0 ]]; then echo "[ERROR] $DEST_KEY"; exit 1; fi
if [[ $DEBUG -eq 1 ]]; then
  echo "[DEBUG] DEST_KEY (first 8 chars): ${DEST_KEY:0:8}..."
  echo "[TRACE] Got destination key, proceeding to file show."
fi

# Confirm file exists in source

if [[ "$TYPE" == "fileshare" ]]; then
  # Get source file properties (mtime)
  if [[ $DEBUG -eq 1 ]]; then
    echo "[DEBUG] az storage file show --account-name $SOURCE_ACCOUNT --account-key [HIDDEN] --share-name $SOURCE_SHARE --path $FILENAME --api-version 2024-03-01 -o json"
  fi
  SRC_PROPS=$(az storage file show \
    --account-name "$SOURCE_ACCOUNT" \
    --account-key "$SOURCE_KEY" \
    --share-name "$SOURCE_SHARE" \
    --path "$FILENAME" \
    --api-version 2024-03-01 \
    -o json 2>/dev/null)
  SRC_EXISTS=$(echo "$SRC_PROPS" | jq -r '.name // empty')
  if [[ -z "$SRC_EXISTS" ]]; then
    echo "File not found in source."
    exit 1
  fi
  SRC_MTIME=$(echo "$SRC_PROPS" | jq -r '.last_modified')
  if [[ -z "$SRC_MTIME" || "$SRC_MTIME" == "null" ]]; then
    echo "Error: last_modified property missing for source file. Raw properties: $SRC_PROPS"
    exit 1
  fi
  SRC_MTIME_EPOCH=$(date -d "$SRC_MTIME" +%s)
  echo "File $FILENAME found in source. mtime: $SRC_MTIME ($SRC_MTIME_EPOCH)"
  # Poll destination for file and get its mtime
  echo "[INFO] Entering destination polling loop for $FILENAME ..."
  ELAPSED=0
  while (( ELAPSED < MAX_WAIT )); do
    echo "[INFO] Polling destination for $FILENAME (elapsed: $ELAPSED seconds) ..."
    if [[ $DEBUG -eq 1 ]]; then
      echo "[DEBUG] az storage file show --account-name $DEST_ACCOUNT --account-key [HIDDEN] --share-name $DEST_SHARE --path $FILENAME --api-version 2024-03-01 -o json"
    fi
    DST_PROPS=$(az storage file show \
      --account-name "$DEST_ACCOUNT" \
      --account-key "$DEST_KEY" \
      --share-name "$DEST_SHARE" \
      --path "$FILENAME" \
      --api-version 2024-03-01 \
      -o json 2>/dev/null)
    DST_EXISTS=$(echo "$DST_PROPS" | jq -r '.name // empty')
    if [[ -n "$DST_EXISTS" ]]; then
      DST_MTIME=$(echo "$DST_PROPS" | jq -r '.last_modified')
      if [[ -z "$DST_MTIME" || "$DST_MTIME" == "null" ]]; then
        echo "Warning: last_modified property missing for destination file. Raw properties: $DST_PROPS"
        sleep "$POLL_INTERVAL"
        ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
        continue
      fi
      DST_MTIME_EPOCH=$(date -d "$DST_MTIME" +%s)
      DURATION=$((DST_MTIME_EPOCH - SRC_MTIME_EPOCH))
      echo "Replication complete: $FILENAME"
      echo "  Type: $TYPE"
      echo "  Source mtime: $SRC_MTIME ($SRC_MTIME_EPOCH)"
      echo "  Destination mtime: $DST_MTIME ($DST_MTIME_EPOCH)"
      echo "  Replication time: $DURATION seconds ($(printf '%02dh:%02dm:%02ds' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60))))"
      echo "$FILENAME,$TYPE,$SRC_MTIME_EPOCH,$DST_MTIME_EPOCH,$DURATION seconds" >> replication_results.csv
      exit 0
    fi
    sleep "$POLL_INTERVAL"
    ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
  done
  echo "Timeout: File did not appear in destination within $MAX_WAIT seconds."
  exit 2
elif [[ "$TYPE" == "datalake" ]]; then
  # Get source file properties (mtime)
  if [[ $DEBUG -eq 1 ]]; then
    echo "[DEBUG] az storage fs file show --account-name $SOURCE_ACCOUNT --account-key [HIDDEN] --file-system $SOURCE_SHARE --path $FILENAME -o json"
  fi
  SRC_PROPS=$(az storage fs file show \
    --account-name "$SOURCE_ACCOUNT" \
    --account-key "$SOURCE_KEY" \
    --file-system "$SOURCE_SHARE" \
    --path "$FILENAME" \
    -o json 2>/dev/null)
  SRC_EXISTS=$(echo "$SRC_PROPS" | jq -r '.name // empty')
  if [[ -z "$SRC_EXISTS" ]]; then
    echo "File not found in source."
    exit 1
  fi
  SRC_MTIME=$(echo "$SRC_PROPS" | jq -r '.last_modified')
  if [[ -z "$SRC_MTIME" || "$SRC_MTIME" == "null" ]]; then
    echo "Error: last_modified property missing for source file. Raw properties: $SRC_PROPS"
    exit 1
  fi
  SRC_MTIME_EPOCH=$(date -d "$SRC_MTIME" +%s)
  echo "File $FILENAME found in source. mtime: $SRC_MTIME ($SRC_MTIME_EPOCH)"
  # Poll destination for file and get its mtime
  ELAPSED=0
  while (( ELAPSED < MAX_WAIT )); do
    if [[ $DEBUG -eq 1 ]]; then
      echo "[DEBUG] az storage fs file show --account-name $DEST_ACCOUNT --account-key [HIDDEN] --file-system $DEST_SHARE --path $FILENAME -o json"
    fi
    DST_PROPS=$(az storage fs file show \
      --account-name "$DEST_ACCOUNT" \
      --account-key "$DEST_KEY" \
      --file-system "$DEST_SHARE" \
      --path "$FILENAME" \
      -o json 2>/dev/null) || true
    DST_EXISTS=$(echo "$DST_PROPS" | jq -r '.name // empty')
    if [[ -n "$DST_EXISTS" ]]; then
      DST_MTIME=$(echo "$DST_PROPS" | jq -r '.last_modified')
      if [[ -z "$DST_MTIME" || "$DST_MTIME" == "null" ]]; then
        echo "Warning: last_modified property missing for destination file. Raw properties: $DST_PROPS"
        sleep "$POLL_INTERVAL"
        ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
        continue
      fi
      DST_MTIME_EPOCH=$(date -d "$DST_MTIME" +%s)
      DURATION=$((DST_MTIME_EPOCH - SRC_MTIME_EPOCH))
      echo "Replication complete: $FILENAME"
      echo "  Type: $TYPE"
      echo "  Source mtime: $SRC_MTIME ($SRC_MTIME_EPOCH)"
      echo "  Destination mtime: $DST_MTIME ($DST_MTIME_EPOCH)"
      echo "  Replication time: $DURATION seconds ($(printf '%02dh:%02dm:%02ds' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60))))"
      echo "$FILENAME,$TYPE,$SRC_MTIME_EPOCH,$DST_MTIME_EPOCH,$DURATION seconds" >> replication_results.csv
      exit 0
    fi
    sleep "$POLL_INTERVAL"
    ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
  done
  echo "Timeout: File did not appear in destination within $MAX_WAIT seconds."
  exit 2
else
  echo "Unknown type: $TYPE. Use 'fileshare' or 'datalake'."
  exit 1
fi
