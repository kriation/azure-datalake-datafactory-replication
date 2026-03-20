#!/usr/bin/env bash
# validate-adf-health.sh
# Minimal health gate for Azure Data Factory replication pipelines.
#
# This script checks:
# 1) Trigger runtime state (optional)
# 2) Latest pipeline run status over a recent time window
#
# Usage:
#   ./scripts/validate-adf-health.sh
#   ./scripts/validate-adf-health.sh --hours 12
#   ./scripts/validate-adf-health.sh --factory dfdemocanadaeast --resource-group rg-demo-canadaeast
#   ./scripts/validate-adf-health.sh --pipelines copydatalakegen2pipeline
#
# Exit codes:
#   0 = healthy for selected pipelines
#   1 = at least one selected pipeline is unhealthy
#   2 = usage/dependency/auth/config error

set -euo pipefail

RESOURCE_GROUP="rg-demo-canadaeast"
DATA_FACTORY="dfdemocanadaeast"
HOURS=6
PIPELINES_CSV="copyfilesharepipeline,copydatalakegen2pipeline"
CHECK_TRIGGERS=true

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -g, --resource-group NAME   Resource group (default: rg-demo-canadaeast)
  -f, --factory NAME          Data Factory name (default: dfdemocanadaeast)
  -w, --hours N               Lookback window in hours (default: 6)
  -p, --pipelines CSV         Comma-separated pipeline names (default: copyfilesharepipeline,copydatalakegen2pipeline)
      --skip-trigger-check    Skip checking trigger runtime state
  -h, --help                  Show this help

Examples:
  ./scripts/validate-adf-health.sh
  ./scripts/validate-adf-health.sh --pipelines copydatalakegen2pipeline
  ./scripts/validate-adf-health.sh --hours 24 --skip-trigger-check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    -f|--factory)
      DATA_FACTORY="$2"
      shift 2
      ;;
    -w|--hours)
      HOURS="$2"
      shift 2
      ;;
    -p|--pipelines)
      PIPELINES_CSV="$2"
      shift 2
      ;;
    --skip-trigger-check)
      CHECK_TRIGGERS=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

for cmd in az jq date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed or not in PATH."
    exit 2
  fi
done

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not authenticated. Run 'az login' first."
  exit 2
fi

if ! [[ "$HOURS" =~ ^[0-9]+$ ]]; then
  echo "Error: --hours must be a positive integer."
  exit 2
fi

START_UTC="$(date -u -d "$HOURS hours ago" +%Y-%m-%dT%H:%M:%SZ)"
END_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

IFS=',' read -r -a PIPELINES <<< "$PIPELINES_CSV"
if [[ "${#PIPELINES[@]}" -eq 0 ]]; then
  echo "Error: no pipelines specified."
  exit 2
fi

echo "[INFO] Factory: $DATA_FACTORY"
echo "[INFO] Resource group: $RESOURCE_GROUP"
echo "[INFO] Lookback window: ${HOURS}h ($START_UTC to $END_UTC)"
echo "[INFO] Pipelines: $PIPELINES_CSV"

declare -A TRIGGER_BY_PIPELINE=(
  [copyfilesharepipeline]=CopyFileShareTrigger
  [copydatalakegen2pipeline]=CopyDataLakeGen2Trigger
)

if [[ "$CHECK_TRIGGERS" == true ]]; then
  echo "[INFO] Checking trigger runtime states..."
  for pipeline in "${PIPELINES[@]}"; do
    trigger_name="${TRIGGER_BY_PIPELINE[$pipeline]:-}"
    if [[ -z "$trigger_name" ]]; then
      echo "[WARN] No trigger mapping defined for pipeline '$pipeline'; skipping trigger check."
      continue
    fi

    state="$(az datafactory trigger show \
      --factory-name "$DATA_FACTORY" \
      --resource-group "$RESOURCE_GROUP" \
      --name "$trigger_name" \
      --query properties.runtimeState -o tsv 2>/dev/null || true)"

    if [[ -z "$state" ]]; then
      echo "[WARN] Trigger '$trigger_name' not found or unreadable."
      continue
    fi

    echo "[INFO] Trigger '$trigger_name' state: $state"
  done
fi

echo "[INFO] Querying recent pipeline runs..."
RUNS_JSON="$(az datafactory pipeline-run query-by-factory \
  --factory-name "$DATA_FACTORY" \
  --resource-group "$RESOURCE_GROUP" \
  --last-updated-after "$START_UTC" \
  --last-updated-before "$END_UTC" \
  -o json)"

fail_count=0

for pipeline in "${PIPELINES[@]}"; do
  latest_run="$(printf '%s' "$RUNS_JSON" | jq -c --arg p "$pipeline" '
    .value
    | map(select(.pipelineName == $p))
    | sort_by(.runStart)
    | last
  ')"

  if [[ -z "$latest_run" || "$latest_run" == "null" ]]; then
    echo "[FAIL] $pipeline: no runs found in lookback window."
    fail_count=$((fail_count + 1))
    continue
  fi

  status="$(printf '%s' "$latest_run" | jq -r '.status // "Unknown"')"
  run_id="$(printf '%s' "$latest_run" | jq -r '.runId // "n/a"')"
  run_start="$(printf '%s' "$latest_run" | jq -r '.runStart // "n/a"')"
  run_end="$(printf '%s' "$latest_run" | jq -r '.runEnd // "n/a"')"
  message="$(printf '%s' "$latest_run" | jq -r '.message // ""')"

  if [[ "$status" == "Succeeded" ]]; then
    echo "[PASS] $pipeline: status=$status runStart=$run_start runEnd=$run_end runId=$run_id"
  else
    echo "[FAIL] $pipeline: status=$status runStart=$run_start runEnd=$run_end runId=$run_id"
    if [[ -n "$message" ]]; then
      echo "       message: $message"
    fi
    fail_count=$((fail_count + 1))
  fi
done

if [[ "$fail_count" -gt 0 ]]; then
  echo "[SUMMARY] Unhealthy pipelines: $fail_count"
  exit 1
fi

echo "[SUMMARY] All selected pipelines are healthy."
exit 0
