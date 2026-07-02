#!/usr/bin/env bash
set -euo pipefail

search_api_version="2025-05-01"

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

prompt_optional_value() {
  local label="$1"
  local user_value=""

  read -r -p "$label: " user_value
  printf '%s' "$user_value"
}

ensure_logged_in() {
  if ! az account show >/dev/null 2>&1; then
    echo "Azure CLI is not logged in. Run 'az login' first." >&2
    exit 1
  fi
}

resolve_role_name() {
  local friendly_name="$1"
  shift

  local candidate
  for candidate in "$@"; do
    local resolved
    resolved="$(az role definition list --name "$candidate" --query '[0].roleName' -o tsv 2>/dev/null || true)"

    if [[ -n "$resolved" ]]; then
      printf '%s' "$resolved"
      return
    fi
  done

  echo "Could not resolve RBAC role for '$friendly_name'. Tried: $*" >&2
  exit 1
}

get_foundry_account_identity() {
  local resource_group="$1"
  local account_name="$2"

  az cognitiveservices account show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --query identity.principalId \
    -o tsv
}

get_foundry_project_identity() {
  local resource_group="$1"
  local account_name="$2"
  local project_name="$3"

  az cognitiveservices account project show \
    --resource-group "$resource_group" \
    --name "$account_name" \
    --project-name "$project_name" \
    --query identity.principalId \
    -o tsv
}

get_search_identity() {
  local resource_group="$1"
  local search_service_name="$2"

  az resource show \
    --resource-group "$resource_group" \
    --resource-type Microsoft.Search/searchServices \
    --name "$search_service_name" \
    --api-version "$search_api_version" \
    --query identity.principalId \
    -o tsv
}

assign_role_if_missing() {
  local principal_object_id="$1"
  local principal_label="$2"
  local role_name="$3"
  local scope="$4"

  local existing
  existing="$(az role assignment list \
    --assignee-object-id "$principal_object_id" \
    --scope "$scope" \
    --role "$role_name" \
    --query 'length(@)' \
    -o tsv)"

  if [[ "$existing" != "0" ]]; then
    echo "Role already assigned: $principal_label -> $role_name"
    return
  fi

  echo "Assigning role: $principal_label -> $role_name"
  az role assignment create \
    --assignee-object-id "$principal_object_id" \
    --assignee-principal-type ServicePrincipal \
    --role "$role_name" \
    --scope "$scope" \
    --output none
}

main() {
  require_command az

  ensure_logged_in

  local resource_group
  local foundry_account_name
  local foundry_project_name
  local search_service_name
  local scope
  local default_scope

  local foundry_hub_principal_id
  local foundry_project_principal_id
  local search_principal_id

  local role_blob_contributor
  local role_cognitive_services_user
  local role_cognitive_services_openai_user
  local role_search_index_data_contributor
  local role_azure_ai_developer

  resource_group="$(prompt_value "Resource group name")"
  foundry_account_name="$(prompt_value "Foundry Hub service name")"
  foundry_project_name="$(prompt_optional_value "Foundry project name (optional)")"
  search_service_name="$(prompt_value "Azure AI Search service name")"

  default_scope="$(az group show --name "$resource_group" --query id -o tsv)"
  scope="$(prompt_value "RBAC scope (resource group/subscription/resource ID)" "$default_scope")"

  foundry_hub_principal_id="$(get_foundry_account_identity "$resource_group" "$foundry_account_name")"
  if [[ -z "$foundry_hub_principal_id" ]]; then
    echo "Foundry Hub account '$foundry_account_name' does not have a managed identity principal ID." >&2
    exit 1
  fi

  if [[ -n "$foundry_project_name" ]]; then
    foundry_project_principal_id="$(get_foundry_project_identity "$resource_group" "$foundry_account_name" "$foundry_project_name")"
    if [[ -z "$foundry_project_principal_id" ]]; then
      echo "Foundry project '$foundry_project_name' does not have a managed identity principal ID." >&2
      exit 1
    fi
  fi

  search_principal_id="$(get_search_identity "$resource_group" "$search_service_name")"
  if [[ -z "$search_principal_id" ]]; then
    echo "Search service '$search_service_name' does not have a managed identity principal ID." >&2
    exit 1
  fi

  # Resolve role display names once so assignment works across minor naming differences.
  role_blob_contributor="$(resolve_role_name "Azure Blob Contributor" "Storage Blob Data Contributor" "Azure Blob Contributor")"
  role_cognitive_services_user="$(resolve_role_name "Cognitive services user" "Cognitive Services User")"
  role_cognitive_services_openai_user="$(resolve_role_name "Cognitive services openai user" "Cognitive Services OpenAI User" "Cognitive Services OpenAI Contributor")"
  role_search_index_data_contributor="$(resolve_role_name "Search Index data contributor" "Search Index Data Contributor")"
  role_azure_ai_developer="$(resolve_role_name "Azure AI Developer" "Azure AI Developer")"

  local all_roles=()
  all_roles+=("$role_blob_contributor")
  all_roles+=("$role_cognitive_services_user")
  all_roles+=("$role_cognitive_services_openai_user")
  all_roles+=("$role_search_index_data_contributor")
  all_roles+=("$role_azure_ai_developer")

  local role_name
  for role_name in "${all_roles[@]}"; do
    assign_role_if_missing "$foundry_hub_principal_id" "Foundry account: $foundry_account_name" "$role_name" "$scope"
    assign_role_if_missing "$search_principal_id" "Search service: $search_service_name" "$role_name" "$scope"

    if [[ -n "$foundry_project_name" ]]; then
      assign_role_if_missing "$foundry_project_principal_id" "Foundry project: $foundry_project_name" "$role_name" "$scope"
    fi
  done

  echo
  echo "Role assignments complete"
  echo "Scope: $scope"
  echo "Foundry hub principal ID: $foundry_hub_principal_id"
  echo "Search principal ID: $search_principal_id"

  if [[ -n "$foundry_project_name" ]]; then
    echo "Foundry project principal ID: $foundry_project_principal_id"
  fi
}

main "$@"