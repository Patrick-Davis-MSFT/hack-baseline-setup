#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${AZURE_ENV_NAME:-}" ]]; then
  echo "AZURE_ENV_NAME is not set." >&2
  exit 1
fi

env_file="$repo_root/.azure/$AZURE_ENV_NAME/.env"
if [[ ! -f "$env_file" ]]; then
  echo "Environment file not found: $env_file" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$env_file"

: "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is not set}"
: "${storageAccountName:?storageAccountName is not set}"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required." >&2
  exit 1
fi

storage_account_key="$(az storage account keys list \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --account-name "$storageAccountName" \
  --query '[0].value' \
  -o tsv)"

if [[ -z "$storage_account_key" ]]; then
  echo "Failed to retrieve a storage account key for $storageAccountName." >&2
  exit 1
fi

coffee_root="$repo_root/data/Coffee"
if [[ ! -d "$coffee_root" ]]; then
  echo "Coffee source folder not found: $coffee_root" >&2
  exit 1
fi

shopt -s nullglob
for source_dir in "$coffee_root"/*/; do
  folder_name="$(basename "${source_dir%/}")"
  container_name="$(tr '[:upper:]' '[:lower:]' <<<"$folder_name")"

  echo "Uploading $source_dir to container $container_name"
  az storage container create \
    --name "$container_name" \
    --account-name "$storageAccountName" \
    --account-key "$storage_account_key" \
    --auth-mode key \
    --only-show-errors >/dev/null

  az storage blob upload-batch \
    --account-name "$storageAccountName" \
    --account-key "$storage_account_key" \
    --auth-mode key \
    --destination "$container_name" \
    --source "$source_dir" \
    --overwrite true \
    --only-show-errors >/dev/null

done
