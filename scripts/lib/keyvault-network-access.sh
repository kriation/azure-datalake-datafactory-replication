#!/usr/bin/env bash
# keyvault-network-access.sh
# Shared helpers for temporarily enabling/disabling Key Vault public
# network access from operator scripts in locked-down environments.

BOOTSTRAP_CIDR="${BOOTSTRAP_CIDR:-}"
KEY_VAULT_ACCESS_OPEN_VAULTS=()

KEYVAULT_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS="${KEYVAULT_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS:-120}"
KEYVAULT_BOOTSTRAP_PROPAGATION_POLL_SECONDS="${KEYVAULT_BOOTSTRAP_PROPAGATION_POLL_SECONDS:-5}"

# ---------------------------------------------------------------------------
# _wait_for_keyvault_network_ready <vault_name>
# Polls until publicNetworkAccess=Enabled and BOOTSTRAP_CIDR is visible.
# ---------------------------------------------------------------------------
_wait_for_keyvault_network_ready() {
  local vault_name="$1"
  local elapsed=0
  local rules_json
  local pna_state ip_rule_count
  local bootstrap_ip="${BOOTSTRAP_CIDR%%/*}"

  while [[ "$elapsed" -lt "$KEYVAULT_BOOTSTRAP_PROPAGATION_TIMEOUT_SECONDS" ]]; do
    pna_state="$(az keyvault show --name "$vault_name" --query properties.publicNetworkAccess -o tsv 2>/dev/null || true)"
    rules_json="$(az keyvault network-rule list --name "$vault_name" -o json 2>/dev/null || true)"

    if [[ -n "$rules_json" ]]; then
      ip_rule_count="$(printf '%s' "$rules_json" | jq -r \
        --arg cidr "$BOOTSTRAP_CIDR" \
        --arg ip "$bootstrap_ip" \
        '[.ipRules[]? | (.value // "") | select(. == $cidr or . == $ip or . == ($ip + "/32") or . == ($ip + "-" + $ip))] | length')"
    else
      ip_rule_count=""
    fi

    if [[ "$pna_state" == "Enabled" && "$ip_rule_count" != "" && "$ip_rule_count" -ge 1 ]]; then
      return
    fi

    sleep "$KEYVAULT_BOOTSTRAP_PROPAGATION_POLL_SECONDS"
    elapsed=$((elapsed + KEYVAULT_BOOTSTRAP_PROPAGATION_POLL_SECONDS))
  done

  echo "Error: temporary Key Vault network bootstrap did not propagate in time for '${vault_name}'."
  echo "       Last observed state: publicNetworkAccess='${pna_state:-unknown}', matchingIpRules='${ip_rule_count:-unknown}'."
  exit 1
}

# ---------------------------------------------------------------------------
# open_key_vault_access <vault_name>
# Enables public network access and adds the operator IP rule.
# ---------------------------------------------------------------------------
open_key_vault_access() {
  local vault_name="$1"

  if [[ -z "$BOOTSTRAP_CIDR" ]]; then
    echo "Error: BOOTSTRAP_CIDR is empty. Call detect_bootstrap_cidr before open_key_vault_access."
    exit 1
  fi

  local existing
  for existing in "${KEY_VAULT_ACCESS_OPEN_VAULTS[@]:-}"; do
    [[ "$existing" == "$vault_name" ]] && return
  done

  echo "[INFO] Temporarily enabling Key Vault network access for '${vault_name}' from ${BOOTSTRAP_CIDR}..."
  echo "[INFO] This exception is temporary and will be removed before the script completes."

  az keyvault update --name "$vault_name" --public-network-access Enabled >/dev/null
  az keyvault network-rule add --name "$vault_name" --ip-address "${BOOTSTRAP_CIDR%%/*}" >/dev/null 2>&1 || true

  _wait_for_keyvault_network_ready "$vault_name"
  KEY_VAULT_ACCESS_OPEN_VAULTS+=("$vault_name")
}

# ---------------------------------------------------------------------------
# close_key_vault_access <vault_name>
# Removes operator IP rule and disables public network access.
# ---------------------------------------------------------------------------
close_key_vault_access() {
  local vault_name="$1"
  local bootstrap_ip="${BOOTSTRAP_CIDR%%/*}"

  echo "[INFO] Restoring Key Vault lockdown for '${vault_name}'..."
  az keyvault network-rule remove --name "$vault_name" --ip-address "$bootstrap_ip" >/dev/null 2>&1 || true
  az keyvault update --name "$vault_name" --public-network-access Disabled >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# close_all_key_vault_access
# Closes all vaults opened by this script. Safe to call from EXIT traps.
# ---------------------------------------------------------------------------
close_all_key_vault_access() {
  local vault_name
  for vault_name in "${KEY_VAULT_ACCESS_OPEN_VAULTS[@]:-}"; do
    [[ -z "$vault_name" ]] && continue
    close_key_vault_access "$vault_name"
  done
  KEY_VAULT_ACCESS_OPEN_VAULTS=()
}
