#!/usr/bin/env bash

IS_SOURCED="false"
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  IS_SOURCED="true"
else
  set -euo pipefail
fi

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Required command not found: $1"
  fi
}

log() {
  echo "$*" >&2
}

fail() {
  log "$*"
  if [[ "$IS_SOURCED" == "true" ]]; then
    return 1
  fi
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Resolve and assign workshop environment variables used by workshop_bootstrap.py and notebooks.

Usage:
  source ./scripts/assign-workshop-env.sh [options]
  eval "$(bash ./scripts/assign-workshop-env.sh [options])"

Options:
  -g, --resource-group <name>      Azure resource group name.
  -f, --foundry-account <name>     Azure AI Foundry account name.
  -p, --foundry-project <name>     Azure AI Foundry project name.
      --auth-mode <mode>           Auth mode: key|managed_identity (prompted in interactive mode).
      --model-zone <value>         Model deployment zone: global|data_zone (default: global).
      --env-file <path>            Write export statements to a file.
      --print                      Print export statements to stdout.
  -h, --help                       Show this help.

Environment variables assigned:
  RESOURCE_GROUP_NAME
  LOCATION
  AZURE_SUBSCRIPTION_ID
  FOUNDRY_ACCOUNT_NAME
  FOUNDRY_PROJECT_NAME
  AZURE_AI_PROJECT_ENDPOINT
  AZURE_AI_PROJECT_API_KEY
  SEARCH_SERVICE_NAME
  SEARCH_API_KEY
  STORAGE_ACCOUNT_NAME
  APPLICATION_INSIGHTS_NAME
  MODEL_DEPLOYMENT_ZONE
  WORKSHOP_AUTH_MODE
EOF
}

normalize_null() {
  local value="${1:-}"
  if [[ "$value" == "null" ]]; then
    printf '%s' ""
    return
  fi
  printf '%s' "$value"
}

prompt_value() {
  local label="$1"
  local default_value="${2:-}"
  local input_value=""

  if [[ ! -t 0 ]]; then
    if [[ -n "$default_value" ]]; then
      printf '%s' "$default_value"
      return
    fi
    fail "Missing required value: $label"
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " input_value
    printf '%s' "${input_value:-$default_value}"
  else
    while [[ -z "$input_value" ]]; do
      read -r -p "$label: " input_value
    done
    printf '%s' "$input_value"
  fi
}

normalize_auth_mode() {
  local raw_value
  raw_value="$(tr '[:upper:]' '[:lower:]' <<<"${1:-}")"

  case "$raw_value" in
    key|keys)
      printf '%s' "key"
      ;;
    managed_identity|managed-identity|managedidentity|mi|msi)
      printf '%s' "managed_identity"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

prompt_auth_mode() {
  local default_value="$1"
  local input_value=""
  local normalized=""

  if [[ ! -t 0 ]]; then
    printf '%s' "$default_value"
    return
  fi

  while true; do
    read -r -p "Authentication mode [key|managed_identity] [$default_value]: " input_value
    input_value="${input_value:-$default_value}"
    normalized="$(normalize_auth_mode "$input_value")"

    if [[ -n "$normalized" ]]; then
      printf '%s' "$normalized"
      return
    fi

    log "Invalid authentication mode '$input_value'. Allowed values: key, managed_identity"
  done
}

ensure_logged_in() {
  if ! az account show >/dev/null 2>&1; then
    fail "Azure CLI is not logged in. Run 'az login' first."
  fi
}

validate_resource_group() {
  local resource_group="$1"
  if ! az group show --name "$resource_group" --query name --output tsv >/dev/null 2>&1; then
    fail "Resource group '$resource_group' was not found."
  fi
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"

  if [[ -z "$option_value" || "$option_value" == -* ]]; then
    fail "Missing value for $option_name"
  fi
}

resolve_single_resource_name() {
  local resource_group="$1"
  local resource_type="$2"
  local name

  name="$(az resource list \
    --resource-group "$resource_group" \
    --resource-type "$resource_type" \
    --query "[0].name" \
    --output tsv 2>/dev/null || true)"

  normalize_null "$name"
}

has_cognitiveservices_commands() {
  az cognitiveservices account list -h >/dev/null 2>&1
}

ensure_cognitiveservices_extension() {
  if has_cognitiveservices_commands; then
    return
  fi

  if az extension show --name cognitiveservices >/dev/null 2>&1; then
    return
  fi

  log "Installing Azure CLI extension: cognitiveservices"
  if az extension add --name cognitiveservices --upgrade --only-show-errors >/dev/null 2>/dev/null; then
    return
  fi

  # Some CLI distributions expose cognitiveservices commands without a separately installable extension.
  if has_cognitiveservices_commands; then
    return
  fi

  log "Unable to install extension 'cognitiveservices'; continuing if built-in commands are available."
}

resolve_foundry_account() {
  local resource_group="$1"
  local explicit_name="$2"
  local resolved_name

  if [[ -n "$explicit_name" ]]; then
    printf '%s' "$explicit_name"
    return
  fi

  resolved_name="$(az cognitiveservices account list \
    --resource-group "$resource_group" \
    --query "[?kind=='AIServices'].name | [0]" \
    --output tsv 2>/dev/null || true)"
  resolved_name="$(normalize_null "$resolved_name")"

  if [[ -z "$resolved_name" ]]; then
    resolved_name="$(az cognitiveservices account list \
      --resource-group "$resource_group" \
      --query "[0].name" \
      --output tsv 2>/dev/null || true)"
    resolved_name="$(normalize_null "$resolved_name")"
  fi

  printf '%s' "$resolved_name"
}

resolve_foundry_project() {
  local resource_group="$1"
  local foundry_account_name="$2"
  local explicit_name="$3"
  local resolved_name
  local project_count

  if [[ -n "$explicit_name" ]]; then
    printf '%s' "$explicit_name"
    return
  fi

  if [[ -z "$foundry_account_name" ]]; then
    printf '%s' ""
    return
  fi

  ensure_cognitiveservices_extension

  project_count="$(az cognitiveservices account project list \
    --name "$foundry_account_name" \
    --resource-group "$resource_group" \
    --query "length(@)" \
    --output tsv 2>/dev/null || true)"
  project_count="$(normalize_null "$project_count")"

  if [[ -z "$project_count" || "$project_count" == "0" ]]; then
    printf '%s' ""
    return
  fi

  resolved_name="$(az cognitiveservices account project list \
    --name "$foundry_account_name" \
    --resource-group "$resource_group" \
    --query "[0].name" \
    --output tsv 2>/dev/null || true)"
  resolved_name="$(normalize_null "$resolved_name")"

  if [[ "$project_count" != "1" ]]; then
    log "Found multiple Foundry projects; using '$resolved_name'. Pass --foundry-project to override."
  fi

  printf '%s' "$resolved_name"
}

resolve_project_endpoint() {
  local resource_group="$1"
  local foundry_account_name="$2"
  local foundry_project_name="$3"
  local endpoint

  if [[ -z "$foundry_account_name" || -z "$foundry_project_name" ]]; then
    printf '%s' ""
    return
  fi

  ensure_cognitiveservices_extension

  endpoint="$(az cognitiveservices account project show \
    --name "$foundry_account_name" \
    --resource-group "$resource_group" \
    --project-name "$foundry_project_name" \
    --query "endpoint" \
    --output tsv 2>/dev/null || true)"
  endpoint="$(normalize_null "$endpoint")"

  if [[ -z "$endpoint" ]]; then
    endpoint="$(az cognitiveservices account project show \
      --name "$foundry_account_name" \
      --resource-group "$resource_group" \
      --project-name "$foundry_project_name" \
      --query "properties.endpoint" \
      --output tsv 2>/dev/null || true)"
    endpoint="$(normalize_null "$endpoint")"
  fi

  if [[ -z "$endpoint" ]]; then
    endpoint="https://${foundry_account_name}.services.ai.azure.com/api/projects/${foundry_project_name}"
  fi

  printf '%s' "$endpoint"
}

resolve_project_api_key() {
  local resource_group="$1"
  local foundry_account_name="$2"
  local key

  if [[ -z "$foundry_account_name" ]]; then
    printf '%s' ""
    return
  fi

  key="$(az cognitiveservices account keys list \
    --resource-group "$resource_group" \
    --name "$foundry_account_name" \
    --query "key1" \
    --output tsv 2>/dev/null || true)"

  normalize_null "$key"
}

resolve_search_api_key() {
  local resource_group="$1"
  local search_service_name="$2"
  local key

  if [[ -z "$search_service_name" ]]; then
    printf '%s' ""
    return
  fi

  key="$(az search admin-key show \
    --resource-group "$resource_group" \
    --service-name "$search_service_name" \
    --query "primaryKey" \
    --output tsv 2>/dev/null || true)"

  normalize_null "$key"
}

build_export_line() {
  local name="$1"
  local value="$2"
  local quoted_value

  printf -v quoted_value '%q' "$value"
  printf 'export %s=%s' "$name" "$quoted_value"
}

main() {
  require_command az

  local is_sourced="$IS_SOURCED"

  local resource_group_name="${RESOURCE_GROUP_NAME:-}"
  local foundry_account_name="${FOUNDRY_ACCOUNT_NAME:-}"
  local foundry_project_name="${FOUNDRY_PROJECT_NAME:-}"
  local foundry_project_endpoint="${AZURE_AI_PROJECT_ENDPOINT:-}"
  local foundry_project_api_key="${AZURE_AI_PROJECT_API_KEY:-}"
  local search_api_key="${SEARCH_API_KEY:-}"
  local model_deployment_zone="${MODEL_DEPLOYMENT_ZONE:-global}"
  local workshop_auth_mode="${WORKSHOP_AUTH_MODE:-key}"

  local env_file=""
  local print_exports="false"
  local resource_group_provided="false"
  local auth_mode_provided="false"

  if [[ "$is_sourced" == "false" ]]; then
    print_exports="true"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -g|--resource-group)
        require_option_value "$1" "${2:-}"
        resource_group_name="${2:-}"
        resource_group_provided="true"
        shift 2
        ;;
      -f|--foundry-account)
        require_option_value "$1" "${2:-}"
        foundry_account_name="${2:-}"
        shift 2
        ;;
      -p|--foundry-project)
        require_option_value "$1" "${2:-}"
        foundry_project_name="${2:-}"
        shift 2
        ;;
      --auth-mode)
        require_option_value "$1" "${2:-}"
        workshop_auth_mode="${2:-}"
        auth_mode_provided="true"
        shift 2
        ;;
      --model-zone)
        require_option_value "$1" "${2:-}"
        model_deployment_zone="${2:-}"
        shift 2
        ;;
      --env-file)
        require_option_value "$1" "${2:-}"
        env_file="${2:-}"
        shift 2
        ;;
      --print)
        print_exports="true"
        shift
        ;;
      -h|--help)
        usage
        if [[ "$is_sourced" == "true" ]]; then
          return 0
        fi
        exit 0
        ;;
      *)
        log "Unknown argument: $1"
        usage
        if [[ "$is_sourced" == "true" ]]; then
          return 1
        fi
        exit 1
        ;;
    esac
  done

  ensure_logged_in

  if [[ "$resource_group_provided" == "true" ]]; then
    if [[ -z "$resource_group_name" ]]; then
      fail "Missing required value: Azure resource group name"
    fi
  else
    resource_group_name="$(prompt_value "Azure resource group name" "$resource_group_name")"
  fi
  validate_resource_group "$resource_group_name"

  workshop_auth_mode="$(normalize_auth_mode "$workshop_auth_mode")"
  if [[ -z "$workshop_auth_mode" ]]; then
    fail "Invalid auth mode. Allowed values: key, managed_identity"
  fi

  if [[ "$auth_mode_provided" != "true" ]]; then
    workshop_auth_mode="$(prompt_auth_mode "$workshop_auth_mode")"
  fi

  model_deployment_zone="$(tr '[:upper:]' '[:lower:]' <<<"$model_deployment_zone")"
  if [[ "$model_deployment_zone" != "global" && "$model_deployment_zone" != "data_zone" ]]; then
    fail "Invalid model zone '$model_deployment_zone'. Allowed values: global, data_zone"
  fi

  local location
  local subscription_id
  local storage_account_name
  local search_service_name
  local application_insights_name

  location="$(az group show --name "$resource_group_name" --query location --output tsv)"
  subscription_id="$(az account show --query id --output tsv)"

  storage_account_name="$(resolve_single_resource_name "$resource_group_name" "Microsoft.Storage/storageAccounts")"
  search_service_name="$(resolve_single_resource_name "$resource_group_name" "Microsoft.Search/searchServices")"
  application_insights_name="$(resolve_single_resource_name "$resource_group_name" "Microsoft.Insights/components")"

  foundry_account_name="$(resolve_foundry_account "$resource_group_name" "$foundry_account_name")"
  foundry_project_name="$(resolve_foundry_project "$resource_group_name" "$foundry_account_name" "$foundry_project_name")"

  if [[ -z "$foundry_project_endpoint" ]]; then
    foundry_project_endpoint="$(resolve_project_endpoint "$resource_group_name" "$foundry_account_name" "$foundry_project_name")"
  fi

  if [[ -z "$foundry_project_api_key" ]]; then
    if [[ "$workshop_auth_mode" == "key" ]]; then
      foundry_project_api_key="$(resolve_project_api_key "$resource_group_name" "$foundry_account_name")"
    else
      foundry_project_api_key=""
    fi
  fi

  if [[ -z "$search_api_key" ]]; then
    if [[ "$workshop_auth_mode" == "key" ]]; then
      search_api_key="$(resolve_search_api_key "$resource_group_name" "$search_service_name")"
    else
      search_api_key=""
    fi
  fi

  if [[ "$workshop_auth_mode" == "managed_identity" ]]; then
    foundry_project_api_key=""
    search_api_key=""
  fi

  local export_lines=()
  export_lines+=("$(build_export_line "RESOURCE_GROUP_NAME" "$resource_group_name")")
  export_lines+=("$(build_export_line "LOCATION" "$location")")
  export_lines+=("$(build_export_line "AZURE_SUBSCRIPTION_ID" "$subscription_id")")
  export_lines+=("$(build_export_line "FOUNDRY_ACCOUNT_NAME" "$foundry_account_name")")
  export_lines+=("$(build_export_line "FOUNDRY_PROJECT_NAME" "$foundry_project_name")")
  export_lines+=("$(build_export_line "AZURE_AI_PROJECT_ENDPOINT" "$foundry_project_endpoint")")
  export_lines+=("$(build_export_line "AZURE_AI_PROJECT_API_KEY" "$foundry_project_api_key")")
  export_lines+=("$(build_export_line "SEARCH_SERVICE_NAME" "$search_service_name")")
  export_lines+=("$(build_export_line "SEARCH_API_KEY" "$search_api_key")")
  export_lines+=("$(build_export_line "STORAGE_ACCOUNT_NAME" "$storage_account_name")")
  export_lines+=("$(build_export_line "APPLICATION_INSIGHTS_NAME" "$application_insights_name")")
  export_lines+=("$(build_export_line "MODEL_DEPLOYMENT_ZONE" "$model_deployment_zone")")
  export_lines+=("$(build_export_line "WORKSHOP_AUTH_MODE" "$workshop_auth_mode")")

  if [[ "$is_sourced" == "true" ]]; then
    export RESOURCE_GROUP_NAME="$resource_group_name"
    export LOCATION="$location"
    export AZURE_SUBSCRIPTION_ID="$subscription_id"
    export FOUNDRY_ACCOUNT_NAME="$foundry_account_name"
    export FOUNDRY_PROJECT_NAME="$foundry_project_name"
    export AZURE_AI_PROJECT_ENDPOINT="$foundry_project_endpoint"
    export AZURE_AI_PROJECT_API_KEY="$foundry_project_api_key"
    export SEARCH_SERVICE_NAME="$search_service_name"
    export SEARCH_API_KEY="$search_api_key"
    export STORAGE_ACCOUNT_NAME="$storage_account_name"
    export APPLICATION_INSIGHTS_NAME="$application_insights_name"
    export MODEL_DEPLOYMENT_ZONE="$model_deployment_zone"
    export WORKSHOP_AUTH_MODE="$workshop_auth_mode"
  fi

  if [[ -n "$env_file" ]]; then
    {
      printf '# Generated by %s on %s\n' "$SCRIPT_NAME" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      for line in "${export_lines[@]}"; do
        printf '%s\n' "$line"
      done
    } >"$env_file"
    log "Wrote environment exports to $env_file"
  fi

  if [[ "$print_exports" == "true" ]]; then
    for line in "${export_lines[@]}"; do
      printf '%s\n' "$line"
    done
  fi

  if [[ "$print_exports" == "false" ]]; then
    log "Workshop environment variables exported in current shell."
  fi

  log "Authentication mode: $workshop_auth_mode"

  if [[ -z "$foundry_account_name" ]]; then
    log "FOUNDRY_ACCOUNT_NAME was not resolved. Set it manually if your workshop requires Foundry notebooks."
  fi

  if [[ -z "$search_service_name" ]]; then
    log "SEARCH_SERVICE_NAME was not resolved. Set it manually if your workshop requires Azure AI Search notebooks."
  fi

  if [[ "$workshop_auth_mode" == "key" ]]; then
    if [[ -z "$foundry_project_api_key" ]]; then
      log "AZURE_AI_PROJECT_API_KEY was not resolved in key mode. Managed identity may still work if RBAC is configured."
    fi
    if [[ -z "$search_api_key" ]]; then
      log "SEARCH_API_KEY was not resolved in key mode. Managed identity may still work if RBAC is configured."
    fi
  fi
}

main "$@"