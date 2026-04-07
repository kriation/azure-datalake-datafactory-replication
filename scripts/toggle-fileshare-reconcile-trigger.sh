#!/bin/bash
#
# Toggle Azure Data Factory file-share delete-reconciliation trigger status (start/stop)

set -e

RESOURCE_GROUP="rg-demo-canadaeast"
DATA_FACTORY="dfdemocanadaeast"
TRIGGER="DeleteReconcileFileShareTrigger"

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
