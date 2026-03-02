#!/bin/bash
# test-replication.sh
# Test runner for Azure file replication timing using existing scripts.
#
# Usage:
#   ./test-replication.sh -t <type> -s <size> -n <num_files> [options]
#
# Options:
#   -t TYPE            fileshare or datalake (required)
#   -s SIZE            File size (e.g., 10M, 100M, 1G; required)
#   -n NUM_FILES       Number of files to test (default: 1)
#   --interval SECS    Poll interval for replication check (default: 10)
#   --max-wait SECS    Max wait for replication (default: 1800)
#   --source-args ARGS Extra args for population script (quoted)
#   --measure-args ARGS Extra args for measure script (quoted)
#
# Example:
#   ./test-replication.sh -t datalake -s 100M -n 2 --interval 5 --max-wait 1200

set -e

# Defaults
NUM_FILES=1
POLL_INTERVAL=10
MAX_WAIT=1800
SOURCE_ARGS=""
MEASURE_ARGS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -t) TYPE="$2"; shift 2;;
    -s) SIZE="$2"; shift 2;;
    -n) NUM_FILES="$2"; shift 2;;
    --interval) POLL_INTERVAL="$2"; shift 2;;
    --max-wait) MAX_WAIT="$2"; shift 2;;
    --source-args) SOURCE_ARGS="$2"; shift 2;;
    --measure-args) MEASURE_ARGS="$2"; shift 2;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done

if [[ -z "$TYPE" || -z "$SIZE" ]]; then
  echo "Type (-t) and size (-s) are required."
  exit 1
fi

# Generate files in source using the appropriate script

if [[ "$TYPE" == "fileshare" ]]; then
  POP_SCRIPT="$(dirname "$0")/populate-source-fileshare.sh"
  NAME_PREFIX="randomfile"
  # Set these to your actual values or make them configurable
  SOURCE_ACCOUNT="stdemoeastus2"
  DEST_ACCOUNT="stdemoeastcanada"
  SOURCE_RG="rg-demo-eastus2"
  DEST_RG="rg-demo-canadaeast"
  SOURCE_SHARE="fileshare"
  DEST_SHARE="fileshare"
elif [[ "$TYPE" == "datalake" ]]; then
  POP_SCRIPT="$(dirname "$0")/populate-source-datalake.sh"
  NAME_PREFIX="randomfile"
  # Set these to your actual values or make them configurable
  SOURCE_ACCOUNT="stdldemoeastus2"
  DEST_ACCOUNT="stdldemocanadaeast"
  SOURCE_RG="rg-demo-eastus2"
  DEST_RG="rg-demo-canadaeast"
  SOURCE_SHARE="fsdleastus2"
  DEST_SHARE="fsdlcanadaeast"
else
  echo "Unknown type: $TYPE. Use 'fileshare' or 'datalake'."
  exit 1
fi


# Run population script and capture uploaded file names
echo "Populating $NUM_FILES file(s) of size $SIZE using $POP_SCRIPT..."
UPLOAD_LOG=$(mktemp)
$POP_SCRIPT -n "$NUM_FILES" -s "$SIZE" $SOURCE_ARGS | tee "$UPLOAD_LOG"

# Extract uploaded file names from the log (look for 'Uploaded <filename>')
FILES=$(grep '^Uploaded ' "$UPLOAD_LOG" | awk '{print $2}')
rm "$UPLOAD_LOG"

# For each uploaded file, run the replication measurement
for FILE in $FILES; do
  echo "Measuring replication for $FILE..."
  "$(dirname "$0")/measure-replication-time.sh" \
    -t "$TYPE" \
    -f "$FILE" \
    -s "$SOURCE_ACCOUNT" \
    -d "$DEST_ACCOUNT" \
    -g "$SOURCE_RG" \
    -h "$DEST_RG" \
    -S "$SOURCE_SHARE" \
    -D "$DEST_SHARE" \
    --interval "$POLL_INTERVAL" \
    --max-wait "$MAX_WAIT" $MEASURE_ARGS
  echo "---"
done

echo "Test run complete. See replication_results.csv for results."
