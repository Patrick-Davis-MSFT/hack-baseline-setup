#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template_file="$repo_root/infra/main.bicep"
parameters_file="$repo_root/infra/main.parameters.json"
coffee_root="$repo_root/data/Coffee"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

prompt_value() {
  local label="$1"
  local default_value="${2:-}"
  local user_value=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " user_value
    printf '%s' "${user_value:-$default_value}"
  else
    while [[ -z "$user_value" ]]; do
      read -r -p "$label: " user_value
    done
    printf '%s' "$user_value"
  fi
}

ensure_logged_in() {
  if ! az account show >/dev/null 2>&1; then
    echo "Azure CLI is not logged in. Run 'az login' first." >&2
    exit 1
  fi
}

ensure_resource_group() {
  local resource_group="$1"
  local location="$2"
  local exists
  exists="$(az group exists --name "$resource_group" -o tsv)"

  if [[ "$exists" == "true" ]]; then
    local existing_location
    existing_location="$(az group show --name "$resource_group" --query location -o tsv)"

    if [[ "$existing_location" != "$location" ]]; then
      echo "Resource group '$resource_group' already exists in '$existing_location', not '$location'." >&2
      exit 1
    fi

    echo "Using existing resource group $resource_group in $existing_location"
    return
  fi

  echo "Creating resource group $resource_group in $location"
  az group create --name "$resource_group" --location "$location" --output none
}

deploy_infrastructure() {
  local resource_group="$1"
  local location="$2"

  echo "Deploying infrastructure from infra/main.bicep" >&2
  az deployment group create \
    --resource-group "$resource_group" \
    --template-file "$template_file" \
    --parameters "@$parameters_file" location="$location" \
    --query properties.outputs.storageAccountName.value \
    -o tsv
}

upload_coffee_docs() {
  local resource_group="$1"
  local storage_account_name="$2"
  local storage_account_key

  storage_account_key="$(az storage account keys list \
    --resource-group "$resource_group" \
    --account-name "$storage_account_name" \
    --query '[0].value' \
    -o tsv)"

  if [[ -z "$storage_account_key" ]]; then
    echo "Failed to retrieve a storage account key for $storage_account_name." >&2
    exit 1
  fi

  shopt -s nullglob
  for source_dir in "$coffee_root"/*/; do
    local folder_name
    local container_name
    folder_name="$(basename "${source_dir%/}")"
    container_name="$(tr '[:upper:]' '[:lower:]' <<<"$folder_name")"

    echo "Uploading $folder_name to container $container_name"
    az storage container create \
      --name "$container_name" \
      --account-name "$storage_account_name" \
      --account-key "$storage_account_key" \
      --auth-mode key \
      --only-show-errors \
      --output none

    az storage blob upload-batch \
      --account-name "$storage_account_name" \
      --account-key "$storage_account_key" \
      --auth-mode key \
      --destination "$container_name" \
      --source "$source_dir" \
      --overwrite true \
      --only-show-errors \
      --output none
  done
}

main() {
  require_command az

  if [[ ! -f "$template_file" ]]; then
    echo "Template file not found: $template_file" >&2
    exit 1
  fi

  if [[ ! -f "$parameters_file" ]]; then
    echo "Parameters file not found: $parameters_file" >&2
    exit 1
  fi

  if [[ ! -d "$coffee_root" ]]; then
    echo "Coffee source folder not found: $coffee_root" >&2
    exit 1
  fi

  ensure_logged_in

  local resource_group
  local location
  local storage_account_name

  resource_group="$(prompt_value "Azure resource group name")"
  location="$(prompt_value "Azure location" "westus")"

  ensure_resource_group "$resource_group" "$location"
  storage_account_name="$(deploy_infrastructure "$resource_group" "$location")"

  if [[ -z "$storage_account_name" ]]; then
    echo "Deployment completed, but the storage account output was not returned." >&2
    exit 1
  fi

  upload_coffee_docs "$resource_group" "$storage_account_name"

  echo
  echo "Deployment complete"
  echo "Resource group: $resource_group"
  echo "Location: $location"
  echo "Storage account: $storage_account_name"
}

main "$@"