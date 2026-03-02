#!/bin/bash
#
# Toggle Azure Data Factory trigger status (start/stop)
#
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - Contributor access to the Data Factory
# - Script is executable: chmod +x scripts/toggle-trigger.sh
#
# Usage:
#   ./toggle-trigger.sh start   # to enable the trigger
#   ./toggle-trigger.sh stop    # to disable the trigger

set -e

RESOURCE_GROUP="rg-demo-canadaeast"
DATA_FACTORY="dfdemocanadaeast"
TRIGGER="CopyFileShareTrigger"

if [[ "$1" == "start" ]]; then
  az datafactory trigger start \
    --factory-name "$DATA_FACTORY" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TRIGGER"
  echo "Trigger $TRIGGER started."
elif [[ "$1" == "stop" ]]; then
  az datafactory trigger stop \
    --factory-name "$DATA_FACTORY" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TRIGGER"
  echo "Trigger $TRIGGER stopped."
else
  echo "Usage: $0 [start|stop]"
  exit 1
fi
