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

prompt_yes_no() {
  local label="$1"
  local default_value="${2:-yes}"
  local user_value=""

  local prompt_suffix="[Y/n]"
  if [[ "$default_value" != "yes" ]]; then
    prompt_suffix="[y/N]"
  fi

  while true; do
    read -r -p "$label $prompt_suffix: " user_value
    user_value="${user_value,,}"

    if [[ -z "$user_value" ]]; then
      user_value="$default_value"
    fi

    case "$user_value" in
      y|yes)
        printf '%s' "true"
        return
        ;;
      n|no)
        printf '%s' "false"
        return
        ;;
      *)
        echo "Please enter yes or no." >&2
        ;;
    esac
  done
}

ensure_logged_in() {
  if ! az account show >/dev/null 2>&1; then
    echo "Azure CLI is not logged in. Run 'az login' first." >&2
    exit 1
  fi
}

ensure_provider_registered() {
  local namespace="$1"
  local state

  state="$(az provider show --namespace "$namespace" --query registrationState -o tsv 2>/dev/null || true)"

  if [[ "$state" == "Registered" ]]; then
    return
  fi

  echo "Registering Azure provider $namespace" >&2
  az provider register --namespace "$namespace" --wait --output none
}

sanitize_name() {
  local input="$1"
  local max_length="$2"
  local cleaned

  cleaned="$(tr '[:upper:]' '[:lower:]' <<<"$input")"
  cleaned="$(tr -cs 'a-z0-9-' '-' <<<"$cleaned")"
  cleaned="${cleaned#-}"
  cleaned="${cleaned%-}"

  if [[ -n "$max_length" && ${#cleaned} -gt "$max_length" ]]; then
    cleaned="${cleaned:0:max_length}"
    cleaned="${cleaned%-}"
  fi

  if [[ -z "$cleaned" ]]; then
    cleaned="wkshop"
  fi

  printf '%s' "$cleaned"
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
    --query properties.outputs \
    -o json
}

foundry_account_exists() {
  local resource_group="$1"
  local account_name="$2"

  az cognitiveservices account show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --query id \
    -o tsv >/dev/null 2>&1
}

wait_for_foundry_account() {
  local resource_group="$1"
  local account_name="$2"
  local max_attempts=90
  local attempt=1

  while (( attempt <= max_attempts )); do
    local state
    state="$(az cognitiveservices account show \
      --resource-group "$resource_group" \
      --name "$account_name" \
      --query properties.provisioningState \
      -o tsv 2>/dev/null || true)"

    case "$state" in
      Succeeded)
        echo "Foundry account $account_name is ready" >&2
        return
        ;;
      Failed|Canceled)
        echo "Foundry account $account_name provisioning failed with state '$state'." >&2
        return 1
        ;;
      *)
        echo "Waiting for Foundry account $account_name (state: ${state:-unknown}, attempt $attempt/$max_attempts)" >&2
        sleep 10
        ;;
    esac

    ((attempt++))
  done

  echo "Timed out waiting for Foundry account $account_name to finish provisioning." >&2
  return 1
}

foundry_project_exists() {
  local resource_group="$1"
  local account_name="$2"
  local project_name="$3"

  az cognitiveservices account project show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --project-name "$project_name" \
    --query id \
    -o tsv >/dev/null 2>&1
}

wait_for_foundry_project() {
  local resource_group="$1"
  local account_name="$2"
  local project_name="$3"
  local max_attempts=90
  local attempt=1

  while (( attempt <= max_attempts )); do
    local state
    state="$(az cognitiveservices account project show \
      --resource-group "$resource_group" \
      --name "$account_name" \
      --project-name "$project_name" \
      --query properties.provisioningState \
      -o tsv 2>/dev/null || true)"

    case "$state" in
      Succeeded)
        echo "Foundry project $project_name is ready" >&2
        return
        ;;
      Failed|Canceled)
        echo "Foundry project $project_name provisioning failed with state '$state'." >&2
        return 1
        ;;
      *)
        echo "Waiting for Foundry project $project_name (state: ${state:-unknown}, attempt $attempt/$max_attempts)" >&2
        sleep 10
        ;;
    esac

    ((attempt++))
  done

  echo "Timed out waiting for Foundry project $project_name to finish provisioning." >&2
  return 1
}

ensure_foundry_account_custom_subdomain() {
  local resource_group="$1"
  local account_name="$2"
  local preferred_subdomain="$3"

  local current_subdomain
  current_subdomain="$(az cognitiveservices account show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --query properties.customSubDomainName \
    -o tsv 2>/dev/null || true)"

  if [[ -n "$current_subdomain" ]]; then
    return
  fi

  echo "Setting custom subdomain on Foundry account $account_name" >&2
  az cognitiveservices account update \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --custom-domain "$preferred_subdomain" \
    --output none

  current_subdomain="$(az cognitiveservices account show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --query properties.customSubDomainName \
    -o tsv 2>/dev/null || true)"

  if [[ -z "$current_subdomain" ]]; then
    echo "Foundry account '$account_name' has no custom subdomain after update. Cannot create projects." >&2
    exit 1
  fi
}

create_foundry_hub() {
  local subscription_id="$1"
  local resource_group="$2"
  local location="$3"
  local hub_name="$4"
  local hub_id="/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.CognitiveServices/accounts/$hub_name"

  if foundry_account_exists "$resource_group" "$hub_name"; then
    local existing_kind
    existing_kind="$(az cognitiveservices account show \
      --resource-group "$resource_group" \
      --name "$hub_name" \
      --query kind \
      -o tsv)"

    if [[ "$existing_kind" != "AIServices" ]]; then
      echo "Resource '$hub_name' already exists but is kind '$existing_kind' (expected 'AIServices')." >&2
      exit 1
    fi

    ensure_foundry_account_custom_subdomain "$resource_group" "$hub_name" "$hub_name"

    echo "Using existing Foundry hub $hub_name" >&2
    printf '%s' "$hub_id"
    return
  fi

  echo "Creating Azure AI Foundry hub $hub_name" >&2
  az cognitiveservices account create \
    --resource-group "$resource_group" \
    --name "$hub_name" \
    --kind AIServices \
    --sku S0 \
    --location "$location" \
    --custom-domain "$hub_name" \
    --assign-identity \
    --allow-project-management true \
    --yes \
    --output none

  wait_for_foundry_account "$resource_group" "$hub_name"
  ensure_foundry_account_custom_subdomain "$resource_group" "$hub_name" "$hub_name"
  printf '%s' "$hub_id"
}

create_foundry_project() {
  local subscription_id="$1"
  local resource_group="$2"
  local location="$3"
  local project_name="$4"
  local account_name="$5"

  local project_id="/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.CognitiveServices/accounts/$account_name/projects/$project_name"

  if foundry_project_exists "$resource_group" "$account_name" "$project_name"; then
    local existing_id
    existing_id="$(az cognitiveservices account project show \
      --resource-group "$resource_group" \
      --name "$account_name" \
      --project-name "$project_name" \
      --query id \
      -o tsv)"

    echo "Using existing Foundry project $project_name" >&2
    printf '%s' "$existing_id"
    return
  fi

  echo "Creating Azure AI Foundry project $project_name" >&2
  az cognitiveservices account project create \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --project-name "$project_name" \
    --location "$location" \
    --display-name "$project_name" \
    --description "Project for the coffee workshop" \
    --assign-identity \
    --output none

  wait_for_foundry_project "$resource_group" "$account_name" "$project_name"
  az cognitiveservices account project show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --project-name "$project_name" \
    --query id \
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
  require_command jq

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
  ensure_provider_registered Microsoft.OperationalInsights


  local resource_group
  local location
  local subscription_id
  local deployment_outputs
  local storage_account_name
  local search_service_name
  local application_insights_name
  local deploy_foundry_resources
  local unique_code
  local default_hub_name=""
  local default_project_name=""
  local foundry_hub_name=""
  local foundry_project_name=""
  local foundry_hub_id=""
  local foundry_project_id=""

  resource_group="$(prompt_value "Azure resource group name")"
  location="$(prompt_value "Azure location" "westus")"
  deploy_foundry_resources="$(prompt_yes_no "Deploy Azure AI Foundry hub and project" "yes")"

  subscription_id="$(az account show --query id -o tsv)"

  ensure_resource_group "$resource_group" "$location"
  deployment_outputs="$(deploy_infrastructure "$resource_group" "$location")"

  storage_account_name="$(jq -r '.storageAccountName.value // empty' <<<"$deployment_outputs")"
  search_service_name="$(jq -r '.searchServiceName.value // empty' <<<"$deployment_outputs")"
  application_insights_name="$(jq -r '.applicationInsightsName.value // empty' <<<"$deployment_outputs")"

  if [[ -z "$storage_account_name" ]]; then
    echo "Deployment completed, but the storage account output was not returned." >&2
    exit 1
  fi

  if [[ "$deploy_foundry_resources" == "true" && ( -z "$search_service_name" || -z "$application_insights_name" ) ]]; then
    echo "Deployment completed, but required Foundry dependency outputs were missing." >&2
    exit 1
  fi

  if [[ "$deploy_foundry_resources" == "true" ]]; then
    ensure_provider_registered Microsoft.CognitiveServices

    unique_code="${storage_account_name: -5}"
    default_hub_name="$(sanitize_name "hub-$resource_group-$unique_code" 33)"
    default_project_name="$(sanitize_name "proj-$resource_group-$unique_code" 33)"

    foundry_hub_name="$(prompt_value "Azure AI Foundry hub name" "$default_hub_name")"
    foundry_hub_name="$(sanitize_name "$foundry_hub_name" 33)"

    foundry_project_name="$(prompt_value "Azure AI Foundry project name" "$default_project_name")"
    foundry_project_name="$(sanitize_name "$foundry_project_name" 33)"

    foundry_hub_id="$(create_foundry_hub \
      "$subscription_id" \
      "$resource_group" \
      "$location" \
      "$foundry_hub_name")"

    foundry_project_id="$(create_foundry_project \
      "$subscription_id" \
      "$resource_group" \
      "$location" \
      "$foundry_project_name" \
      "$foundry_hub_name")"
  else
    echo "Skipping Azure AI Foundry hub/project creation by request."
  fi

  upload_coffee_docs "$resource_group" "$storage_account_name"

  echo
  echo "Deployment complete"
  echo "Resource group: $resource_group"
  echo "Location: $location"
  echo "Storage account: $storage_account_name"
  echo "Search service: $search_service_name"
  echo "Application Insights: $application_insights_name"

  if [[ "$deploy_foundry_resources" == "true" ]]; then
    echo "Foundry hub: $foundry_hub_name"
    echo "Foundry hub ID: $foundry_hub_id"
    echo "Foundry project: $foundry_project_name"
    echo "Foundry project ID: $foundry_project_id"
  else
    echo "Foundry hub/project deployment: skipped"
  fi
}

main "$@"