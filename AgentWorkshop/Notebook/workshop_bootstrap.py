from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import requests
from azure.identity import DefaultAzureCredential


class WorkshopConstants:
    ENV_RESOURCE_GROUP_NAME = "RESOURCE_GROUP_NAME"
    ENV_LOCATION = "LOCATION"
    ENV_SUBSCRIPTION_ID = "AZURE_SUBSCRIPTION_ID"
    ENV_FOUNDRY_ACCOUNT_NAME = "FOUNDRY_ACCOUNT_NAME"
    ENV_FOUNDRY_PROJECT_NAME = "FOUNDRY_PROJECT_NAME"
    ENV_FOUNDRY_PROJECT_ENDPOINT = "AZURE_AI_PROJECT_ENDPOINT"
    ENV_FOUNDRY_PROJECT_API_KEY = "AZURE_AI_PROJECT_API_KEY"
    ENV_SEARCH_SERVICE_NAME = "SEARCH_SERVICE_NAME"
    ENV_SEARCH_API_KEY = "SEARCH_API_KEY"
    ENV_STORAGE_ACCOUNT_NAME = "STORAGE_ACCOUNT_NAME"
    ENV_APPLICATION_INSIGHTS_NAME = "APPLICATION_INSIGHTS_NAME"
    ENV_MODEL_ZONE = "MODEL_DEPLOYMENT_ZONE"

    MODEL_ZONE_GLOBAL = "global"
    MODEL_ZONE_DATA_ZONE = "data_zone"
    MODEL_SKU_BY_ZONE = {
        MODEL_ZONE_GLOBAL: "GlobalStandard",
        MODEL_ZONE_DATA_ZONE: "DataZoneStandard",
    }

    CHAT_MODEL_CANDIDATES = (
        "gpt-4.1",
        "gpt-4.1-mini",
        "gpt-4o-mini",
    )
    EMBEDDING_MODEL_CANDIDATES = (
        "text-embedding-3-small",
        "text-embedding-3-large",
    )

    DEFAULT_DEPLOYMENT_CAPACITY = 1
    DEFAULT_TIMEOUT_SECONDS = 120
    DEFAULT_POLL_SECONDS = 5
    DEFAULT_MAX_POLLS = 36

    SEARCH_SCOPE = "https://search.azure.com/.default"
    SEARCH_API_VERSION = "2026-05-01-preview"
    SEARCH_SEMANTIC_CONFIG = "default-semantic-config"

    RESOURCE_TYPE_STORAGE = "Microsoft.Storage/storageAccounts"
    RESOURCE_TYPE_SEARCH = "Microsoft.Search/searchServices"
    RESOURCE_TYPE_APP_INSIGHTS = "Microsoft.Insights/components"
    RESOURCE_TYPE_COG_SERVICES = "Microsoft.CognitiveServices/accounts"


@dataclass(slots=True)
class WorkshopConfig:
    resource_group_name: str
    location: str
    subscription_id: str
    foundry_account_name: str
    foundry_project_name: str
    foundry_project_endpoint: str
    foundry_project_api_key: str
    search_service_name: str
    search_api_key: str
    storage_account_name: str
    application_insights_name: str
    model_zone: str

    @property
    def search_endpoint(self) -> str:
        return f"https://{self.search_service_name}.search.windows.net"

    @property
    def storage_blob_endpoint(self) -> str:
        return f"https://{self.storage_account_name}.blob.core.windows.net"

    @property
    def openai_resource_endpoint(self) -> str:
        if self.foundry_project_endpoint:
            return re.sub(r"/api/projects/.*$", "", self.foundry_project_endpoint)
        return ""

    def as_dict(self, redact_secrets: bool = True) -> dict[str, Any]:
        data = asdict(self)
        if redact_secrets:
            for field_name in ("foundry_project_api_key", "search_api_key"):
                if data.get(field_name):
                    data[field_name] = "***"
        return data

    def show(self) -> None:
        print(json.dumps(self.as_dict(), indent=2))


def run_command(command: list[str], expect_json: bool = False) -> Any:
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    stdout = completed.stdout.strip()
    if expect_json:
        return json.loads(stdout) if stdout else {}
    return stdout


def run_az(command_args: list[str], expect_json: bool = False) -> Any:
    full_command = ["az", *command_args]
    if expect_json and "-o" not in command_args and "--output" not in command_args:
        full_command.extend(["--output", "json"])
    return run_command(full_command, expect_json=expect_json)


def _resolve_account_show() -> dict[str, Any]:
    return run_az(["account", "show"], expect_json=True)


def _resolve_group_show(resource_group_name: str) -> dict[str, Any]:
    return run_az(["group", "show", "--name", resource_group_name], expect_json=True)


def _resolve_resource_names(resource_group_name: str) -> dict[str, str]:
    resources = run_az(["resource", "list", "--resource-group", resource_group_name], expect_json=True)
    by_type: dict[str, str] = {}
    for resource in resources:
        resource_type = resource.get("type", "")
        resource_name = resource.get("name", "")
        if resource_type and resource_name and resource_type not in by_type:
            by_type[resource_type] = resource_name
    return by_type


def _project_name_from_endpoint(project_endpoint: str) -> str:
    if "/api/projects/" not in project_endpoint:
        return ""
    return project_endpoint.split("/api/projects/")[-1].strip("/")


def build_workshop_config(overrides: dict[str, str] | None = None) -> WorkshopConfig:
    override_values = overrides or {}

    resource_group_name = override_values.get("resource_group_name") or os.getenv(WorkshopConstants.ENV_RESOURCE_GROUP_NAME, "")
    if not resource_group_name:
        raise ValueError(
            "Missing RESOURCE_GROUP_NAME. Set the environment variable or pass {'resource_group_name': '<name>'}."
        )

    account = _resolve_account_show()
    group = _resolve_group_show(resource_group_name)
    names_by_type = _resolve_resource_names(resource_group_name)

    subscription_id = (
        override_values.get("subscription_id")
        or os.getenv(WorkshopConstants.ENV_SUBSCRIPTION_ID, "")
        or account.get("id", "")
    )

    location = (
        override_values.get("location")
        or os.getenv(WorkshopConstants.ENV_LOCATION, "")
        or group.get("location", "")
    )

    storage_account_name = (
        override_values.get("storage_account_name")
        or os.getenv(WorkshopConstants.ENV_STORAGE_ACCOUNT_NAME, "")
        or names_by_type.get(WorkshopConstants.RESOURCE_TYPE_STORAGE, "")
    )

    search_service_name = (
        override_values.get("search_service_name")
        or os.getenv(WorkshopConstants.ENV_SEARCH_SERVICE_NAME, "")
        or names_by_type.get(WorkshopConstants.RESOURCE_TYPE_SEARCH, "")
    )

    search_api_key = (
        override_values.get("search_api_key")
        or os.getenv(WorkshopConstants.ENV_SEARCH_API_KEY, "")
    )

    application_insights_name = (
        override_values.get("application_insights_name")
        or os.getenv(WorkshopConstants.ENV_APPLICATION_INSIGHTS_NAME, "")
        or names_by_type.get(WorkshopConstants.RESOURCE_TYPE_APP_INSIGHTS, "")
    )

    foundry_account_name = (
        override_values.get("foundry_account_name")
        or os.getenv(WorkshopConstants.ENV_FOUNDRY_ACCOUNT_NAME, "")
        or names_by_type.get(WorkshopConstants.RESOURCE_TYPE_COG_SERVICES, "")
    )

    foundry_project_endpoint = (
        override_values.get("foundry_project_endpoint")
        or os.getenv(WorkshopConstants.ENV_FOUNDRY_PROJECT_ENDPOINT, "")
    )

    foundry_project_api_key = (
        override_values.get("foundry_project_api_key")
        or os.getenv(WorkshopConstants.ENV_FOUNDRY_PROJECT_API_KEY, "")
    )

    foundry_project_name = (
        override_values.get("foundry_project_name")
        or os.getenv(WorkshopConstants.ENV_FOUNDRY_PROJECT_NAME, "")
    )

    if not foundry_project_name and foundry_project_endpoint:
        foundry_project_name = _project_name_from_endpoint(foundry_project_endpoint)

    if not foundry_project_endpoint and foundry_account_name and foundry_project_name:
        foundry_project_endpoint = (
            f"https://{foundry_account_name}.services.ai.azure.com/api/projects/{foundry_project_name}"
        )

    model_zone = (
        override_values.get("model_zone")
        or os.getenv(WorkshopConstants.ENV_MODEL_ZONE, WorkshopConstants.MODEL_ZONE_GLOBAL)
    ).strip().lower()

    if model_zone not in WorkshopConstants.MODEL_SKU_BY_ZONE:
        allowed_values = ", ".join(WorkshopConstants.MODEL_SKU_BY_ZONE.keys())
        raise ValueError(f"Invalid model zone '{model_zone}'. Allowed values: {allowed_values}")

    return WorkshopConfig(
        resource_group_name=resource_group_name,
        location=location,
        subscription_id=subscription_id,
        foundry_account_name=foundry_account_name,
        foundry_project_name=foundry_project_name,
        foundry_project_endpoint=foundry_project_endpoint,
        foundry_project_api_key=foundry_project_api_key,
        search_service_name=search_service_name,
        search_api_key=search_api_key,
        storage_account_name=storage_account_name,
        application_insights_name=application_insights_name,
        model_zone=model_zone,
    )


def ensure_cognitiveservices_extension() -> None:
    run_az(["extension", "add", "--name", "cognitiveservices", "--upgrade"])


def get_available_models(config: WorkshopConfig) -> list[dict[str, Any]]:
    return run_az(
        [
            "cognitiveservices",
            "account",
            "list-models",
            "--name",
            config.foundry_account_name,
            "--resource-group",
            config.resource_group_name,
        ],
        expect_json=True,
    )


def _first_sku_name(model: dict[str, Any]) -> str:
    skus = model.get("skus", [])
    if not skus:
        return ""
    return skus[0].get("name", "")


def _first_sku_capacity(model: dict[str, Any]) -> int:
    skus = model.get("skus", [])
    if not skus:
        return WorkshopConstants.DEFAULT_DEPLOYMENT_CAPACITY
    return int(skus[0].get("capacity", {}).get("default", WorkshopConstants.DEFAULT_DEPLOYMENT_CAPACITY))


def select_model_definition(
    available_models: list[dict[str, Any]],
    model_candidates: tuple[str, ...],
    preferred_sku: str,
) -> dict[str, Any]:
    for candidate_name in model_candidates:
        matching_models = [m for m in available_models if m.get("name") == candidate_name]
        if not matching_models:
            continue

        sku_match = [m for m in matching_models if _first_sku_name(m) == preferred_sku]
        if sku_match:
            return sku_match[0]
        return matching_models[0]

    raise ValueError(
        "No matching model found for candidates: "
        + ", ".join(model_candidates)
        + ". Run get_available_models(config) to inspect options in your subscription."
    )


def deploy_model(
    config: WorkshopConfig,
    deployment_name: str,
    model_name: str,
    model_version: str,
    model_format: str,
    sku_name: str,
    sku_capacity: int,
) -> dict[str, Any]:
    run_az(
        [
            "cognitiveservices",
            "account",
            "deployment",
            "create",
            "--name",
            config.foundry_account_name,
            "--resource-group",
            config.resource_group_name,
            "--deployment-name",
            deployment_name,
            "--model-name",
            model_name,
            "--model-version",
            model_version,
            "--model-format",
            model_format,
            "--sku-name",
            sku_name,
            "--sku-capacity",
            str(sku_capacity),
        ]
    )

    return run_az(
        [
            "cognitiveservices",
            "account",
            "deployment",
            "show",
            "--name",
            config.foundry_account_name,
            "--resource-group",
            config.resource_group_name,
            "--deployment-name",
            deployment_name,
        ],
        expect_json=True,
    )


def list_deployments(config: WorkshopConfig) -> list[dict[str, Any]]:
    return run_az(
        [
            "cognitiveservices",
            "account",
            "deployment",
            "list",
            "--name",
            config.foundry_account_name,
            "--resource-group",
            config.resource_group_name,
        ],
        expect_json=True,
    )


def ensure_models_deployed(config: WorkshopConfig) -> dict[str, str]:
    ensure_cognitiveservices_extension()
    available_models = get_available_models(config)
    preferred_sku = WorkshopConstants.MODEL_SKU_BY_ZONE[config.model_zone]

    chat_model = select_model_definition(
        available_models=available_models,
        model_candidates=WorkshopConstants.CHAT_MODEL_CANDIDATES,
        preferred_sku=preferred_sku,
    )
    embedding_model = select_model_definition(
        available_models=available_models,
        model_candidates=WorkshopConstants.EMBEDDING_MODEL_CANDIDATES,
        preferred_sku=preferred_sku,
    )

    chat_deployment_name = chat_model["name"].replace(".", "-").lower()
    embedding_deployment_name = embedding_model["name"].replace(".", "-").lower()

    deploy_model(
        config=config,
        deployment_name=chat_deployment_name,
        model_name=chat_model["name"],
        model_version=str(chat_model["version"]),
        model_format=chat_model["format"],
        sku_name=_first_sku_name(chat_model) or preferred_sku,
        sku_capacity=_first_sku_capacity(chat_model),
    )

    deploy_model(
        config=config,
        deployment_name=embedding_deployment_name,
        model_name=embedding_model["name"],
        model_version=str(embedding_model["version"]),
        model_format=embedding_model["format"],
        sku_name=_first_sku_name(embedding_model) or preferred_sku,
        sku_capacity=_first_sku_capacity(embedding_model),
    )

    return {
        "chat_deployment_name": chat_deployment_name,
        "embedding_deployment_name": embedding_deployment_name,
        "chat_model_name": chat_model["name"],
        "embedding_model_name": embedding_model["name"],
        "deployment_sku": preferred_sku,
    }


class SearchRestClient:
    def __init__(self, endpoint: str, api_key: str = "") -> None:
        self.endpoint = endpoint.rstrip("/")

        if api_key:
            self.headers = {
                "api-key": api_key,
                "Content-Type": "application/json",
            }
        else:
            token = DefaultAzureCredential().get_token(WorkshopConstants.SEARCH_SCOPE).token
            self.headers = {
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            }

    def put(self, path: str, payload: dict[str, Any]) -> None:
        url = f"{self.endpoint}/{path}?api-version={WorkshopConstants.SEARCH_API_VERSION}"
        response = requests.put(url, headers=self.headers, json=payload, timeout=WorkshopConstants.DEFAULT_TIMEOUT_SECONDS)
        response.raise_for_status()

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.endpoint}/{path}?api-version={WorkshopConstants.SEARCH_API_VERSION}"
        response = requests.post(url, headers=self.headers, json=payload, timeout=WorkshopConstants.DEFAULT_TIMEOUT_SECONDS)
        response.raise_for_status()
        return response.json() if response.content else {}


def build_search_client(config: WorkshopConfig) -> SearchRestClient:
    return SearchRestClient(config.search_endpoint, api_key=config.search_api_key)


def build_project_client(config: WorkshopConfig) -> Any:
    if not config.foundry_project_endpoint:
        raise ValueError("Missing foundry_project_endpoint in workshop configuration.")

    from azure.ai.projects import AIProjectClient

    if config.foundry_project_api_key:
        from azure.core.credentials import AzureKeyCredential

        return AIProjectClient(
            endpoint=config.foundry_project_endpoint,
            credential=AzureKeyCredential(config.foundry_project_api_key),
        )

    return AIProjectClient(
        endpoint=config.foundry_project_endpoint,
        credential=DefaultAzureCredential(),
    )


def create_search_index(client: SearchRestClient, index_name: str) -> None:
    body = {
        "name": index_name,
        "fields": [
            {"name": "id", "type": "Edm.String", "key": True, "filterable": True},
            {"name": "title", "type": "Edm.String", "searchable": True, "retrievable": True},
            {"name": "content", "type": "Edm.String", "searchable": True, "retrievable": True},
            {"name": "sourcePath", "type": "Edm.String", "filterable": True, "retrievable": True},
            {"name": "sourceType", "type": "Edm.String", "filterable": True, "retrievable": True},
        ],
        "semantic": {
            "configurations": [
                {
                    "name": WorkshopConstants.SEARCH_SEMANTIC_CONFIG,
                    "prioritizedFields": {
                        "titleField": {"fieldName": "title"},
                        "prioritizedContentFields": [{"fieldName": "content"}],
                    },
                }
            ]
        },
    }
    client.put(f"indexes/{index_name}", body)


def upload_documents(client: SearchRestClient, index_name: str, documents: list[dict[str, str]]) -> None:
    actions = [{"@search.action": "mergeOrUpload", **doc} for doc in documents]
    client.post(f"indexes/{index_name}/docs/index", {"value": actions})


def create_knowledge_source(client: SearchRestClient, knowledge_source_name: str, index_name: str) -> None:
    body = {
        "name": knowledge_source_name,
        "kind": "searchIndex",
        "searchIndexParameters": {
            "searchIndexName": index_name,
            "semanticConfigurationName": WorkshopConstants.SEARCH_SEMANTIC_CONFIG,
            "sourceDataFields": [{"name": "title"}, {"name": "content"}, {"name": "sourcePath"}],
            "searchFields": [],
        },
    }
    client.put(f"knowledgesources/{knowledge_source_name}", body)


def create_knowledge_base(
    client: SearchRestClient,
    knowledge_base_name: str,
    knowledge_source_names: list[str],
    azure_openai_resource_uri: str,
    chat_deployment_name: str,
    chat_model_name: str,
) -> None:
    body = {
        "name": knowledge_base_name,
        "description": "Coffee workshop Foundry IQ knowledge base.",
        "knowledgeSources": [{"name": knowledge_source_name} for knowledge_source_name in knowledge_source_names],
        "outputMode": "answerSynthesis",
        "retrievalReasoningEffort": {"kind": "medium"},
        "models": [
            {
                "kind": "azureOpenAI",
                "azureOpenAIParameters": {
                    "resourceUri": azure_openai_resource_uri.rstrip("/"),
                    "deploymentId": chat_deployment_name,
                    "modelName": chat_model_name,
                },
            }
        ],
    }
    client.put(f"knowledgebases/{knowledge_base_name}", body)


def sanitize_name(raw_value: str) -> str:
    lowered = raw_value.lower()
    alnum_hyphen = re.sub(r"[^a-z0-9-]", "-", lowered)
    compact = re.sub(r"-+", "-", alnum_hyphen).strip("-")
    return compact


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
