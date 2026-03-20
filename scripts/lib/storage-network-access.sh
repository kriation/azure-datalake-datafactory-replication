#!/usr/bin/env bash
# storage-network-access.sh
# Shared helpers for temporarily enabling/disabling storage account public
# network access from operator scripts running against Phase 4 locked-down
# environments.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/storage-network-access.sh"
#   detect_bootstrap_cidr
#   open_storage_account_access <account_name> <resource_group>
#   open_storage_account_access <account_name2> <resource_group2>
#   trap 'close_all_storage_access' EXIT
#   # ... do data-plane work ...
#   # trap fires on exit and restores lockdown
#
# All opened accounts are tracked in STORAGE_ACCESS_OPEN_ACCOUNTS and
# restored to Disabled public network access on close_all_storage_access.

BOOTSTRAP_CIDR="${BOOTSTRAP_CIDR:-}"
STORAGE_ACCESS_OPEN_ACCOUNTS=()

STORAGE_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS="${STORAGE_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS:-120}"
STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS="${STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS:-5}"
# The storage file/blob data plane may lag the management API by 30-60 seconds after
# a network rule change. Use a conservative sleep so uploads/downloads don't hit 403s.
STORAGE_BOOTSTRAP_POST_READY_SLEEP_SECONDS="${STORAGE_BOOTSTRAP_POST_READY_SLEEP_SECONDS:-30}"

# ---------------------------------------------------------------------------
# detect_bootstrap_cidr
# Detects the current operator's public IP and sets BOOTSTRAP_CIDR (<ip>/32).
# No-op if BOOTSTRAP_CIDR is already set.
# ---------------------------------------------------------------------------
detect_bootstrap_cidr() {
  if [[ -n "$BOOTSTRAP_CIDR" ]]; then
    return
  fi

  local public_ip
  public_ip="$(curl -fsSL https://api.ipify.org)"
  if [[ -z "$public_ip" ]]; then
    echo "Error: unable to determine the current public IP for storage network bootstrap."
    exit 1
  fi

  BOOTSTRAP_CIDR="${public_ip}/32"
}

# ---------------------------------------------------------------------------
# _storage_ip_rule_present <account_name> <resource_group> <cidr>
# Returns 0 if the given CIDR/IP is already in the account's IP rules.
# ---------------------------------------------------------------------------
_storage_ip_rule_present() {
  local account_name="$1"
  local resource_group="$2"
  local cidr="$3"
  local ip_only="${cidr%%/*}"
  local rules_json existing_count

  rules_json="$(az storage account network-rule list --account-name "$account_name" --resource-group "$resource_group" -o json 2>/dev/null || true)"
  if [[ -z "$rules_json" ]]; then
    return 1
  fi

  existing_count="$(printf '%s' "$rules_json" | jq -r \
    --arg cidr "$cidr" --arg ip "$ip_only" \
    '[.ipRules[]? | (.value // .iPAddressOrRange // .ipAddressOrRange // "") | select(. == $cidr or . == $ip or . == ($ip + "/32") or . == ($ip + "-" + $ip))] | length')"
  [[ "$existing_count" -ge 1 ]]
}

# ---------------------------------------------------------------------------
# _add_storage_network_rule <account_name> <resource_group> <cidr>
# ---------------------------------------------------------------------------
_add_storage_network_rule() {
  local account_name="$1"
  local resource_group="$2"
  local cidr="$3"
  local ip_only="${cidr%%/*}"

  if _storage_ip_rule_present "$account_name" "$resource_group" "$cidr"; then
    return
  fi

  if az storage account network-rule add \
      --account-name "$account_name" \
      --resource-group "$resource_group" \
      --ip-address "$ip_only" \
      --only-show-errors >/dev/null 2>&1; then
    return
  fi

  # Rule may have been added by a concurrent caller; check once more.
  if _storage_ip_rule_present "$account_name" "$resource_group" "$cidr"; then
    return
  fi

  echo "Error: failed to apply temporary storage firewall rule for '$ip_only' on account '$account_name'."
  exit 1
}

# ---------------------------------------------------------------------------
# _remove_storage_network_rule <account_name> <resource_group> <cidr>
# ---------------------------------------------------------------------------
_remove_storage_network_rule() {
  local account_name="$1"
  local resource_group="$2"
  local cidr="$3"
  local ip_only="${cidr%%/*}"

  az storage account network-rule remove \
    --account-name "$account_name" \
    --resource-group "$resource_group" \
    --ip-address "$ip_only" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# _wait_for_storage_network_ready <account_name> <resource_group>
# Polls until publicNetworkAccess=Enabled and BOOTSTRAP_CIDR IP rule is visible.
# ---------------------------------------------------------------------------
_wait_for_storage_network_ready() {
  local account_name="$1"
  local resource_group="$2"
  local elapsed=0
  local storage_state pna_state ip_rule_count
  local bootstrap_ip="${BOOTSTRAP_CIDR%%/*}"

  while [[ "$elapsed" -lt "$STORAGE_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS" ]]; do
    storage_state="$(az storage account show \
      --name "$account_name" \
      --resource-group "$resource_group" \
      -o json 2>/dev/null || true)"

    if [[ -n "$storage_state" ]]; then
      pna_state="$(printf '%s' "$storage_state" | jq -r '.publicNetworkAccess // empty')"
      ip_rule_count="$(printf '%s' "$storage_state" | jq -r \
        --arg cidr "$BOOTSTRAP_CIDR" --arg ip "$bootstrap_ip" \
        '[(.networkRuleSet.ipRules // [])[] | (.value // .iPAddressOrRange // .ipAddressOrRange // "") | select(. == $cidr or . == $ip or . == ($ip + "/32") or . == ($ip + "-" + $ip))] | length')"

      if [[ "$pna_state" == "Enabled" && "$ip_rule_count" != "" && "$ip_rule_count" -ge 1 ]]; then
        return
      fi
    fi

    sleep "$STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS"
    elapsed=$((elapsed + STORAGE_BOOTSTRAP_PROPAGATION_POLL_SECONDS))
  done

  echo "Error: temporary storage network bootstrap did not propagate in time for '${account_name}'."
  echo "       Last observed state: publicNetworkAccess='${pna_state:-unknown}', matchingIpRules='${ip_rule_count:-unknown}'."
  exit 1
}

# ---------------------------------------------------------------------------
# open_storage_account_access <account_name> <resource_group>
# Enables public network access (with Deny default) and adds the operator's
# IP rule. Waits for propagation. Idempotent — skips if already opened by
# this script invocation.
# ---------------------------------------------------------------------------
open_storage_account_access() {
  local account_name="$1"
  local resource_group="$2"
  local key="${account_name}:${resource_group}"

  if [[ -z "$BOOTSTRAP_CIDR" ]]; then
    echo "Error: call detect_bootstrap_cidr before open_storage_account_access."
    exit 1
  fi

  # Idempotency: skip if already opened in this script run.
  local entry
  for entry in "${STORAGE_ACCESS_OPEN_ACCOUNTS[@]:-}"; do
    [[ "$entry" == "$key" ]] && return
  done

  echo "[INFO] Temporarily enabling storage network access for '${account_name}' from ${BOOTSTRAP_CIDR}..."
  echo "[INFO] This exception is temporary and will be removed before the script completes."

  az storage account update \
    --name "$account_name" \
    --resource-group "$resource_group" \
    --public-network-access Enabled \
    --default-action Deny >/dev/null

  _add_storage_network_rule "$account_name" "$resource_group" "$BOOTSTRAP_CIDR"
  _wait_for_storage_network_ready "$account_name" "$resource_group"

  sleep "$STORAGE_BOOTSTRAP_POST_READY_SLEEP_SECONDS"

  STORAGE_ACCESS_OPEN_ACCOUNTS+=("$key")
}

# ---------------------------------------------------------------------------
# close_storage_account_access <account_name> <resource_group>
# Removes the operator IP rule and disables public network access.
# ---------------------------------------------------------------------------
close_storage_account_access() {
  local account_name="$1"
  local resource_group="$2"

  echo "[INFO] Restoring storage lockdown for '${account_name}'..."
  _remove_storage_network_rule "$account_name" "$resource_group" "$BOOTSTRAP_CIDR"
  az storage account update \
    --name "$account_name" \
    --resource-group "$resource_group" \
    --public-network-access Disabled >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# close_all_storage_access
# Closes all accounts opened by this script. Safe to call from EXIT traps.
# ---------------------------------------------------------------------------
close_all_storage_access() {
  local entry account_name resource_group
  for entry in "${STORAGE_ACCESS_OPEN_ACCOUNTS[@]:-}"; do
    [[ -z "$entry" ]] && continue
    account_name="${entry%%:*}"
    resource_group="${entry#*:}"
    close_storage_account_access "$account_name" "$resource_group"
  done
  STORAGE_ACCESS_OPEN_ACCOUNTS=()
}

# ---------------------------------------------------------------------------
# wait_for_storage_account_data_plane <service_type> <account_name> <account_key> [timeout_seconds]
# Polls the storage data-plane endpoint (using the supplied account key) until
# the service accepts requests, or until timeout_seconds (default: 120) elapses.
#   service_type: "file"  — Azure File service  (az storage share list)
#                 "dfs"   — Azure Data Lake Gen2 (az storage fs list)
# Call this after open_storage_account_access + account key retrieval so the
# actual data-plane enforcement has caught up before any file operations run.
# ---------------------------------------------------------------------------
wait_for_storage_account_data_plane() {
  local service_type="$1"
  local account_name="$2"
  local account_key="$3"
  local timeout="${4:-120}"
  local elapsed=0
  local result

  while (( elapsed < timeout )); do
    result=0
    if [[ "$service_type" == "file" ]]; then
      az storage share list \
        --account-name "$account_name" \
        --account-key "$account_key" \
        -o none 2>/dev/null || result=$?
    else
      az storage fs list \
        --account-name "$account_name" \
        --account-key "$account_key" \
        -o none 2>/dev/null || result=$?
    fi

    if [[ "$result" -eq 0 ]]; then
      return
    fi

    echo "[INFO] Waiting for '${account_name}' (${service_type}) data plane to become accessible (${elapsed}/${timeout}s)..."
    sleep 10
    elapsed=$((elapsed + 10))
  done

  echo "Error: storage data plane for '${account_name}' (${service_type}) did not become accessible within ${timeout} seconds."
  exit 1
}
