#!/usr/bin/env bash
# reset-to-keyvault-baseline.sh
# Purges all resources except the two resource groups and two empty Key Vaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
TFVARS_FILE="demo.tfvars"
AUTO_APPROVE=true
DRY_RUN=false
PRESERVE_CHECKPOINT_AUDIT=true

# shellcheck source=lib/storage-network-access.sh
source "$SCRIPT_DIR/lib/storage-network-access.sh"
# shellcheck source=lib/keyvault-network-access.sh
source "$SCRIPT_DIR/lib/keyvault-network-access.sh"

tfvar_string() {
  local variable_name="$1"
  local line

  line="$(grep -E "^[[:space:]]*${variable_name}[[:space:]]*=" "$TFVARS_PATH" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi

  echo "$line" | awk -F'"' '{print $2}'
}

tf_output_or_tfvar() {
  local output_name="$1"
  local tfvar_name="$2"
  local value

  value="$(tf output -raw "$output_name" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    echo "$value"
    return
  fi

  tfvar_string "$tfvar_name"
}

tf_state_rm_if_present() {
  local address="$1"

  if tf state show "$address" >/dev/null 2>&1; then
    tf state rm "$address" >/dev/null
  fi
}

current_principal_object_id() {
  local oid=""

  oid="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$oid" && "$oid" != "null" ]]; then
    echo "$oid"
    return
  fi

  local account_user
  account_user="$(az account show --query user.name -o tsv 2>/dev/null || true)"
  if [[ -n "$account_user" ]]; then
    oid="$(az ad sp show --id "$account_user" --query id -o tsv 2>/dev/null || true)"
    if [[ -n "$oid" && "$oid" != "null" ]]; then
      echo "$oid"
      return
    fi
  fi

  echo ""
}

current_principal_type() {
  local account_type

  account_type="$(az account show --query user.type -o tsv 2>/dev/null || true)"
  case "$account_type" in
    user)
      echo "User"
      ;;
    servicePrincipal)
      echo "ServicePrincipal"
      ;;
    *)
      echo ""
      ;;
  esac
}

has_role_on_scope() {
  local scope="$1"
  local principal_id="$2"
  local role_name="$3"
  local count

  count="$(az role assignment list --scope "$scope" --assignee-object-id "$principal_id" --include-inherited --query "[?roleDefinitionName=='${role_name}'] | length(@)" -o tsv 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -gt 0 ]]
}

can_manage_role_assignments_on_scope() {
  local scope="$1"
  local principal_id="$2"

  has_role_on_scope "$scope" "$principal_id" "Owner" \
    || has_role_on_scope "$scope" "$principal_id" "User Access Administrator" \
    || has_role_on_scope "$scope" "$principal_id" "Role Based Access Control Administrator"
}

ensure_key_vault_administrator() {
  local kv_scope="$1"
  local principal_id="$2"
  local principal_type="$3"

  if has_role_on_scope "$kv_scope" "$principal_id" "Key Vault Administrator"; then
    return 0
  fi

  if can_manage_role_assignments_on_scope "$kv_scope" "$principal_id"; then
    echo "[INFO] Current principal is missing Key Vault Administrator on ${kv_scope}; attempting to grant it automatically..."

    if [[ -n "$principal_type" ]]; then
      az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "$principal_type" \
        --role "Key Vault Administrator" \
        --scope "$kv_scope" >/dev/null
    else
      az role assignment create \
        --assignee-object-id "$principal_id" \
        --role "Key Vault Administrator" \
        --scope "$kv_scope" >/dev/null
    fi

    return 0
  fi

  echo "Error: current principal lacks Key Vault Administrator on ${kv_scope}."
  echo "       Reset destroys Key Vault keys/secrets, so Terraform needs Key Vault data-plane admin on both vaults."
  echo "       Grant it with: az role assignment create --assignee-object-id ${principal_id} --role \"Key Vault Administrator\" --scope ${kv_scope}"
  echo "       If your current identity only has Contributor, an Owner/User Access Administrator must run that command."
  exit 1
}

preflight_permissions() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[INFO] DRY RUN: skipping RBAC preflight checks."
    return 0
  fi

  local principal_id principal_type subscription_id east_rg canada_rg east_kv canada_kv
  local east_rg_scope canada_rg_scope east_kv_scope canada_kv_scope

  principal_id="$(current_principal_object_id)"
  if [[ -z "$principal_id" ]]; then
    echo "Error: unable to resolve current principal object ID for RBAC preflight checks."
    echo "       Ensure Azure CLI login context is valid and retry."
    exit 1
  fi

  subscription_id="$(az account show --query id -o tsv)"
  principal_type="$(current_principal_type)"
  east_rg="$(tf_output_or_tfvar eastus2_rg_name eastus2_rg_name)"
  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name)"
  east_kv="$(tf_output_or_tfvar eastus2_key_vault_name eastus2_key_vault_name)"
  canada_kv="$(tf_output_or_tfvar canadaeast_key_vault_name canadaeast_key_vault_name)"

  east_rg_scope="/subscriptions/${subscription_id}/resourceGroups/${east_rg}"
  canada_rg_scope="/subscriptions/${subscription_id}/resourceGroups/${canada_rg}"
  east_kv_scope="${east_rg_scope}/providers/Microsoft.KeyVault/vaults/${east_kv}"
  canada_kv_scope="${canada_rg_scope}/providers/Microsoft.KeyVault/vaults/${canada_kv}"

  if ! has_role_on_scope "$east_rg_scope" "$principal_id" "Owner" && ! has_role_on_scope "$east_rg_scope" "$principal_id" "Contributor"; then
    echo "Error: current principal lacks Owner/Contributor on ${east_rg_scope}."
    echo "       This reset requires write/delete permissions at RG scope."
    exit 1
  fi

  if ! has_role_on_scope "$canada_rg_scope" "$principal_id" "Owner" && ! has_role_on_scope "$canada_rg_scope" "$principal_id" "Contributor"; then
    echo "Error: current principal lacks Owner/Contributor on ${canada_rg_scope}."
    echo "       This reset requires write/delete permissions at RG scope."
    exit 1
  fi

  ensure_key_vault_administrator "$east_kv_scope" "$principal_id" "$principal_type"
  ensure_key_vault_administrator "$canada_kv_scope" "$principal_id" "$principal_type"
}

bootstrap_acl_access() {
  local east_rg canada_rg
  local east_kv canada_kv
  local east_storage canada_storage
  local east_datalake canada_datalake

  if [[ "$DRY_RUN" == true ]]; then
    echo "[INFO] DRY RUN: skipping temporary network ACL bootstrap updates."
    return 0
  fi

  east_rg="$(tf_output_or_tfvar eastus2_rg_name eastus2_rg_name || true)"
  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name || true)"
  east_kv="$(tf_output_or_tfvar eastus2_key_vault_name eastus2_key_vault_name || true)"
  canada_kv="$(tf_output_or_tfvar canadaeast_key_vault_name canadaeast_key_vault_name || true)"
  east_storage="$(tf_output_or_tfvar eastus2_storage_name eastus2_storage_name || true)"
  canada_storage="$(tf_output_or_tfvar canadaeast_storage_name canadaeast_storage_name || true)"
  east_datalake="$(tf_output_or_tfvar eastus2_datalake_storage_name eastus2_datalake_storage_name || true)"
  canada_datalake="$(tf_output_or_tfvar canadaeast_datalake_storage_name canadaeast_datalake_storage_name || true)"

  detect_bootstrap_cidr
  trap 'close_all_key_vault_access' EXIT

  echo "[INFO] Applying temporary network ACL bootstrap rules before teardown..."

  if [[ -n "$east_kv" ]] && az keyvault show --name "$east_kv" >/dev/null 2>&1; then
    open_key_vault_access "$east_kv"
  else
    echo "[WARN] East US 2 Key Vault not found; skipping temporary ACL bootstrap for Key Vault."
  fi

  if [[ -n "$canada_kv" ]] && az keyvault show --name "$canada_kv" >/dev/null 2>&1; then
    open_key_vault_access "$canada_kv"
  else
    echo "[WARN] Canada East Key Vault not found; skipping temporary ACL bootstrap for Key Vault."
  fi

  if [[ -n "$east_storage" && -n "$east_rg" ]] && az storage account show --name "$east_storage" --resource-group "$east_rg" >/dev/null 2>&1; then
    open_storage_account_access "$east_storage" "$east_rg"
  else
    echo "[WARN] East US 2 file-share storage account not found; skipping temporary ACL bootstrap for storage."
  fi

  if [[ -n "$canada_storage" && -n "$canada_rg" ]] && az storage account show --name "$canada_storage" --resource-group "$canada_rg" >/dev/null 2>&1; then
    open_storage_account_access "$canada_storage" "$canada_rg"
  else
    echo "[WARN] Canada East file-share storage account not found; skipping temporary ACL bootstrap for storage."
  fi

  if [[ -n "$east_datalake" && -n "$east_rg" ]] && az storage account show --name "$east_datalake" --resource-group "$east_rg" >/dev/null 2>&1; then
    open_storage_account_access "$east_datalake" "$east_rg"
  else
    echo "[WARN] East US 2 Data Lake storage account not found; skipping temporary ACL bootstrap for storage."
  fi

  if [[ -n "$canada_datalake" && -n "$canada_rg" ]] && az storage account show --name "$canada_datalake" --resource-group "$canada_rg" >/dev/null 2>&1; then
    open_storage_account_access "$canada_datalake" "$canada_rg"
  else
    echo "[WARN] Canada East Data Lake storage account not found; skipping temporary ACL bootstrap for storage."
  fi
}

delete_adf_foundation() {
  local canada_rg data_factory_name

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] az datafactory delete --resource-group <canadaeast-rg> --name <data-factory> --yes"
    echo "[DRY RUN] az deployment group delete --resource-group <canadaeast-rg> --name adf-pipeline-deployment"
    echo "[DRY RUN] terraform state rm module.data_factory.azurerm_resource_group_template_deployment.pipeline"
    echo "[DRY RUN] terraform state rm module.data_factory_identity.azurerm_data_factory.this"
    echo "[DRY RUN] terraform state rm azurerm_data_factory_customer_managed_key.canadaeast_data_factory_cmk_binding"
    return 0
  fi

  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name || true)"
  data_factory_name="$(tf_output_or_tfvar data_factory_name data_factory_name || true)"

  if [[ -z "$canada_rg" || -z "$data_factory_name" ]]; then
    echo "[WARN] Unable to resolve Data Factory coordinates; skipping direct ADF teardown bootstrap."
    return 0
  fi

  if az datafactory show --resource-group "$canada_rg" --name "$data_factory_name" >/dev/null 2>&1; then
    echo "[INFO] Deleting Data Factory directly via Azure CLI to avoid Terraform ARM template nested-delete ordering failures..."
    az datafactory delete --resource-group "$canada_rg" --name "$data_factory_name" --yes >/dev/null
  fi

  if az deployment group show --resource-group "$canada_rg" --name adf-pipeline-deployment >/dev/null 2>&1; then
    echo "[INFO] Deleting ADF ARM deployment record..."
    az deployment group delete --resource-group "$canada_rg" --name adf-pipeline-deployment >/dev/null
  fi

  tf_state_rm_if_present module.data_factory.azurerm_resource_group_template_deployment.pipeline
  tf_state_rm_if_present module.data_factory_identity.azurerm_data_factory.this
  tf_state_rm_if_present azurerm_data_factory_customer_managed_key.canadaeast_data_factory_cmk_binding
}

purge_soft_deleted_cmk_keys() {
  local east_kv canada_kv

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Purging soft-deleted CMK keys from both Key Vaults..."
    return 0
  fi

  east_kv="$(tf_output_or_tfvar eastus2_key_vault_name eastus2_key_vault_name || true)"
  canada_kv="$(tf_output_or_tfvar canadaeast_key_vault_name canadaeast_key_vault_name || true)"

  purge_vault_deleted_keys() {
    local vault_name="$1"
    [[ -z "$vault_name" ]] && return 0
    az keyvault key list-deleted --vault-name "$vault_name" --query '[].name' -o tsv 2>/dev/null | while read -r key_name; do
      if [[ -n "$key_name" ]]; then
        echo "[INFO] Purging soft-deleted key '${key_name}' from '${vault_name}'..."
        az keyvault key purge --vault-name "$vault_name" --name "$key_name" >/dev/null 2>&1 || true
      fi
    done
  }

  if [[ -n "$east_kv" ]]; then
    purge_vault_deleted_keys "$east_kv"
  fi

  if [[ -n "$canada_kv" ]]; then
    purge_vault_deleted_keys "$canada_kv"
  fi
}

remove_stale_cmk_bindings_from_state() {
  # Remove CMK binding resources from Terraform state if their keys no longer exist.
  # This prevents Terraform from trying to unbind keys that have already been purged.
  
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Removing stale CMK binding resources from Terraform state..."
    return 0
  fi

  tf_state_rm_if_present 'azurerm_storage_account_customer_managed_key.eastus2_storage_cmk_binding'
  tf_state_rm_if_present 'azurerm_storage_account_customer_managed_key.eastus2_datalake_cmk_binding'
  tf_state_rm_if_present 'azurerm_storage_account_customer_managed_key.canadaeast_storage_cmk_binding'
  tf_state_rm_if_present 'azurerm_storage_account_customer_managed_key.canadaeast_datalake_cmk_binding'
}

delete_key_vault_artifacts() {
  local east_kv canada_kv
  local east_storage_key east_datalake_key
  local canada_storage_key canada_datalake_key canada_adf_key
  local source_secret dest_secret

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] az keyvault key delete --vault-name <east-kv> --name <east-storage-cmk>"
    echo "[DRY RUN] az keyvault key delete --vault-name <east-kv> --name <east-datalake-cmk>"
    echo "[DRY RUN] az keyvault key delete --vault-name <canada-kv> --name <canada-storage-cmk>"
    echo "[DRY RUN] az keyvault key delete --vault-name <canada-kv> --name <canada-datalake-cmk>"
    echo "[DRY RUN] az keyvault key delete --vault-name <canada-kv> --name <canada-adf-cmk>"
    echo "[DRY RUN] az keyvault secret delete --vault-name <canada-kv> --name <source-secret>"
    echo "[DRY RUN] az keyvault secret delete --vault-name <canada-kv> --name <dest-secret>"
    return 0
  fi

  east_kv="$(tf_output_or_tfvar eastus2_key_vault_name eastus2_key_vault_name || true)"
  canada_kv="$(tf_output_or_tfvar canadaeast_key_vault_name canadaeast_key_vault_name || true)"
  east_storage_key="$(tfvar_string eastus2_storage_cmk_name || true)"
  east_datalake_key="$(tfvar_string eastus2_datalake_cmk_name || true)"
  canada_storage_key="$(tfvar_string canadaeast_storage_cmk_name || true)"
  canada_datalake_key="$(tfvar_string canadaeast_datalake_cmk_name || true)"
  canada_adf_key="$(tfvar_string canadaeast_data_factory_cmk_name || true)"
  source_secret="$(tfvar_string data_factory_source_fileshare_connection_secret_name || true)"
  dest_secret="$(tfvar_string data_factory_dest_fileshare_connection_secret_name || true)"

  delete_key_if_present() {
    local vault_name="$1"
    local key_name="$2"
    [[ -z "$vault_name" || -z "$key_name" ]] && return 0
    if az keyvault key show --vault-name "$vault_name" --name "$key_name" >/dev/null 2>&1; then
      echo "[INFO] Deleting Key Vault key '${key_name}' from '${vault_name}' via Azure CLI..."
      az keyvault key delete --vault-name "$vault_name" --name "$key_name" >/dev/null
    fi
  }

  delete_secret_if_present() {
    local vault_name="$1"
    local secret_name="$2"
    [[ -z "$vault_name" || -z "$secret_name" ]] && return 0
    if az keyvault secret show --vault-name "$vault_name" --name "$secret_name" >/dev/null 2>&1; then
      echo "[INFO] Deleting Key Vault secret '${secret_name}' from '${vault_name}' via Azure CLI..."
      az keyvault secret delete --vault-name "$vault_name" --name "$secret_name" >/dev/null
    fi
  }

  delete_key_if_present "$east_kv" "$east_storage_key"
  delete_key_if_present "$east_kv" "$east_datalake_key"
  delete_key_if_present "$canada_kv" "$canada_storage_key"
  delete_key_if_present "$canada_kv" "$canada_datalake_key"
  delete_key_if_present "$canada_kv" "$canada_adf_key"
  delete_secret_if_present "$canada_kv" "$source_secret"
  delete_secret_if_present "$canada_kv" "$dest_secret"

  tf_state_rm_if_present 'module.eastus2_encryption_keys.azurerm_key_vault_key.this["cmk-st-eastus2"]'
  tf_state_rm_if_present 'module.eastus2_encryption_keys.azurerm_key_vault_key.this["cmk-dl-eastus2"]'
  tf_state_rm_if_present 'module.canadaeast_encryption_keys.azurerm_key_vault_key.this["cmk-st-canadaeast"]'
  tf_state_rm_if_present 'module.canadaeast_encryption_keys.azurerm_key_vault_key.this["cmk-dl-canadaeast"]'
  tf_state_rm_if_present 'module.canadaeast_encryption_keys.azurerm_key_vault_key.this["cmk-adf-canadaeast"]'
  tf_state_rm_if_present azurerm_key_vault_secret.adf_source_fileshare_connection_string
  tf_state_rm_if_present azurerm_key_vault_secret.adf_dest_fileshare_connection_string
  tf_state_rm_if_present time_sleep.eastus2_key_vault_rbac_propagation
  tf_state_rm_if_present time_sleep.canadaeast_key_vault_rbac_propagation
}

validate_reset_result() {
  local east_rg canada_rg
  local extra_live=0 extra_state=0
  local live_output state_output state_line
  local retries=0 max_retries=6 retry_delay=5

  east_rg="$(tf_output_or_tfvar eastus2_rg_name eastus2_rg_name)"
  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name)"

  while [[ $retries -lt $max_retries ]]; do
    extra_live=0
    extra_state=0

    live_output="$(
      for rg in "$east_rg" "$canada_rg"; do
        az resource list -g "$rg" --query "[?type!='Microsoft.KeyVault/vaults'].{rg:resourceGroup,type:type,name:name}" -o tsv 2>/dev/null || true
      done
    )"

    state_output="$(tf state list 2>/dev/null || true)"

    while IFS= read -r state_line; do
      [[ -z "$state_line" ]] && continue
      case "$state_line" in
        data.azurerm_client_config.current|module.eastus2_rg.azurerm_resource_group.this|module.canadaeast_rg.azurerm_resource_group.this|module.eastus2_key_vault.azurerm_key_vault.this|module.canadaeast_key_vault.azurerm_key_vault.this)
          ;;
        *)
          extra_state=1
          ;;
      esac
    done <<< "$state_output"

    if [[ -n "$live_output" ]]; then
      extra_live=1
    fi

    if [[ "$extra_live" -eq 0 && "$extra_state" -eq 0 ]]; then
      echo "[PASS] Purge complete. Only resource groups and empty Key Vaults are retained."
      return 0
    fi

    if [[ $retries -lt $((max_retries - 1)) ]]; then
      if [[ "$extra_live" -eq 1 ]]; then
        echo "[INFO] Waiting for async Azure deletions to complete (${retries}/${max_retries} retries)..."
      fi
      sleep "$retry_delay"
      ((retries++))
    else
      break
    fi
  done

  echo "[FAIL] Reset validation failed. Unexpected resources or Terraform state entries remain."
  if [[ "$extra_live" -eq 1 ]]; then
    echo "[FAIL] Live Azure resources still present outside the two Key Vaults:"
    printf '%s\n' "$live_output"
  fi
  if [[ "$extra_state" -eq 1 ]]; then
    echo "[FAIL] Terraform state still contains entries beyond the two RGs and two Key Vaults:"
    printf '%s\n' "$state_output" | grep -Ev '^(data\.azurerm_client_config\.current|module\.eastus2_rg\.azurerm_resource_group\.this|module\.canadaeast_rg\.azurerm_resource_group\.this|module\.eastus2_key_vault\.azurerm_key_vault\.this|module\.canadaeast_key_vault\.azurerm_key_vault\.this)$' || true
  fi
  return 1

  east_rg="$(tf_output_or_tfvar eastus2_rg_name eastus2_rg_name)"
  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name)"

  live_output="$(
    for rg in "$east_rg" "$canada_rg"; do
      az resource list -g "$rg" --query "[?type!='Microsoft.KeyVault/vaults'].{rg:resourceGroup,type:type,name:name}" -o tsv 2>/dev/null || true
    done
  )"

  state_output="$(tf state list 2>/dev/null || true)"

  while IFS= read -r state_line; do
    [[ -z "$state_line" ]] && continue
    case "$state_line" in
      data.azurerm_client_config.current|module.eastus2_rg.azurerm_resource_group.this|module.canadaeast_rg.azurerm_resource_group.this|module.eastus2_key_vault.azurerm_key_vault.this|module.canadaeast_key_vault.azurerm_key_vault.this)
        ;;
      *)
        extra_state=1
        ;;
    esac
  done <<< "$state_output"

  if [[ -n "$live_output" ]]; then
    extra_live=1
  fi

  if [[ "$extra_live" -eq 1 || "$extra_state" -eq 1 ]]; then
    echo "[FAIL] Reset validation failed. Unexpected resources or Terraform state entries remain."
    if [[ "$extra_live" -eq 1 ]]; then
      echo "[FAIL] Live Azure resources still present outside the two Key Vaults:"
      printf '%s\n' "$live_output"
    fi
    if [[ "$extra_state" -eq 1 ]]; then
      echo "[FAIL] Terraform state still contains entries beyond the two RGs and two Key Vaults:"
      printf '%s\n' "$state_output" | grep -Ev '^(data\.azurerm_client_config\.current|module\.eastus2_rg\.azurerm_resource_group\.this|module\.canadaeast_rg\.azurerm_resource_group\.this|module\.eastus2_key_vault\.azurerm_key_vault\.this|module\.canadaeast_key_vault\.azurerm_key_vault\.this)$' || true
    fi
    return 1
  fi

  echo "[PASS] Purge complete. Only resource groups and empty Key Vaults are retained."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -f, --tfvars FILE      Terraform var-file name under terraform/ (default: demo.tfvars)
  --no-auto-approve      Disable -auto-approve in terraform destroy calls
  --dry-run              Print actions without executing
  --preserve-checkpoint-audit
                          Keep checkpoint audit artifacts when immutability mode is strict-regulated (default: true)
  --no-preserve-checkpoint-audit
                          Force teardown attempt of checkpoint audit artifacts (demo-regulated mode expectation)
  -h, --help             Show this help

What this keeps:
  - Resource groups
  - Regional Key Vaults (empty)

What this removes:
  - Phase 3 CMKs and related RBAC/data-factory-identity resources
  - Phase 4 storage + datalake resources and storage CMK bindings
  - Phase 5/6 ADF resources, ADF CMK binding, ADF storage RBAC, and ADF KV secrets
  - Key Vault private endpoints and Phase 1 network resources (VNets/subnets/private DNS)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--tfvars)
      TFVARS_FILE="$2"
      shift 2
      ;;
    --no-auto-approve)
      AUTO_APPROVE=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --preserve-checkpoint-audit)
      PRESERVE_CHECKPOINT_AUDIT=true
      shift
      ;;
    --no-preserve-checkpoint-audit)
      PRESERVE_CHECKPOINT_AUDIT=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

TFVARS_PATH="$TF_DIR/$TFVARS_FILE"
if [[ ! -f "$TFVARS_PATH" ]]; then
  echo "Error: var-file not found: $TFVARS_PATH"
  exit 1
fi

for cmd in terraform az jq curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI is not authenticated. Run 'az login' first."
  exit 1
fi

TF_APPROVE_ARGS=()
if [[ "$AUTO_APPROVE" == true ]]; then
  TF_APPROVE_ARGS+=("-auto-approve")
fi

PHASE4_ARGS=("--cleanup-all" "-f" "$TFVARS_FILE")
if [[ "$AUTO_APPROVE" == false ]]; then
  PHASE4_ARGS+=("--no-auto-approve")
fi

tf() {
  terraform -chdir="$TF_DIR" "$@"
}

pre_destroy_checkpoint_governance_cleanup() {
  local checkpoint_storage checkpoint_container immutability_mode
  local canada_rg

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Checking/removing checkpoint immutability policy prior to destroy (demo-regulated mode)."
    return 0
  fi

  checkpoint_storage="$(tf_output_or_tfvar canadaeast_checkpoint_storage_name canadaeast_checkpoint_storage_name || true)"
  checkpoint_container="$(tf_output_or_tfvar adf_checkpoint_container_name adf_checkpoint_container_name || true)"
  immutability_mode="$(tfvar_string adf_checkpoint_immutability_mode || true)"
  canada_rg="$(tf_output_or_tfvar canadaeast_rg_name canadaeast_rg_name || true)"

  if [[ -z "$immutability_mode" ]]; then
    immutability_mode="demo-regulated"
  fi

  if [[ "$immutability_mode" == "strict-regulated" && "$PRESERVE_CHECKPOINT_AUDIT" == true ]]; then
    echo "[INFO] strict-regulated mode with preserve flag enabled; skipping checkpoint immutability removal."
    return 0
  fi

  if [[ -z "$checkpoint_storage" || -z "$checkpoint_container" || -z "$canada_rg" ]]; then
    echo "[WARN] Checkpoint storage/container not configured; skipping immutability cleanup."
    return 0
  fi

  if ! az storage account show --name "$checkpoint_storage" --resource-group "$canada_rg" >/dev/null 2>&1; then
    echo "[INFO] Checkpoint storage account '${checkpoint_storage}' not found; skipping immutability cleanup."
    return 0
  fi

  echo "[INFO] Attempting checkpoint immutability cleanup on ${checkpoint_storage}/${checkpoint_container}..."

  az storage container immutability-policy delete \
    --account-name "$checkpoint_storage" \
    --container-name "$checkpoint_container" \
    --if-match '*' \
    --auth-mode login >/dev/null 2>&1 || true
}

destroy_phase56() {
  echo "[INFO] Destroying Phase 5/6 resources (ADF + ADF CMK + KV secrets + ADF storage RBAC)..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] terraform -chdir=$TF_DIR destroy -refresh=false ... -var-file=$TFVARS_FILE"
    return 0
  fi

  tf destroy \
    -refresh=false \
    -target=azurerm_role_assignment.adf_to_eastus2_fileshare \
    -target=azurerm_role_assignment.adf_to_canadaeast_fileshare \
    -target=azurerm_role_assignment.adf_to_eastus2_datalake \
    -target=azurerm_role_assignment.adf_to_canadaeast_datalake \
    -target=azurerm_role_assignment.canadaeast_data_factory_key_vault_crypto_user \
    -target=azurerm_role_assignment.canadaeast_data_factory_key_vault_secrets_user \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}"
}

destroy_phase4_and_phase3() {
  echo "[INFO] Destroying Phase 4 and Phase 3 while retaining Key Vaults and lower-phase prerequisites..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] $SCRIPT_DIR/test-phase4-storage-cmk-tls.sh ${PHASE4_ARGS[*]}"
    return 0
  fi

  "$SCRIPT_DIR/test-phase4-storage-cmk-tls.sh" "${PHASE4_ARGS[@]}"
}

destroy_kv_private_endpoints_and_network() {
  echo "[INFO] Destroying Key Vault private endpoints and network foundation (keeping Key Vaults + RGs)..."

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] terraform -chdir=$TF_DIR destroy -refresh=false -target=module.eastus2_key_vault.azurerm_private_endpoint.this -target=module.canadaeast_key_vault.azurerm_private_endpoint.this -target=module.eastus2_network -target=module.canadaeast_network -var-file=$TFVARS_FILE"
    return 0
  fi

  tf destroy \
    -refresh=false \
    -target=module.eastus2_key_vault.azurerm_private_endpoint.this \
    -target=module.canadaeast_key_vault.azurerm_private_endpoint.this \
    -target=module.eastus2_network \
    -target=module.canadaeast_network \
    -var-file="$TFVARS_FILE" \
    "${TF_APPROVE_ARGS[@]}"
}

echo "[INFO] Initializing Terraform..."
if [[ "$DRY_RUN" == false ]]; then
  tf init -upgrade=false >/dev/null
fi

echo "[INFO] Running RBAC preflight checks..."
preflight_permissions

bootstrap_acl_access
purge_soft_deleted_cmk_keys
remove_stale_cmk_bindings_from_state
delete_adf_foundation
pre_destroy_checkpoint_governance_cleanup

destroy_phase56
destroy_phase4_and_phase3

# Delete Key Vault artifacts AFTER CMK bindings are removed from storage
delete_key_vault_artifacts

destroy_kv_private_endpoints_and_network

validate_reset_result
