# Foundry IQ + Agent Workflow Workshop Baseline (`azd` + Bicep)

This repository is an `azd` infrastructure-only project that provisions **one resource group** with:

- Azure Storage Account (Blob Storage enabled, `Standard_LRS`, shared key access enabled)
- Azure AI Search (`standard` SKU, key-based auth)
- Azure AI Foundry Hub + Project
- Azure OpenAI account with:
  - embedding deployment (default: `text-embedding-3-large`)
  - chat deployment (default: `gpt-4o-mini`)

## Region guardrails

The Bicep template only allows these regions:

- `eastus2`
- `swedencentral`
- `francecentral`

These are the documented US regions where Microsoft Foundry projects are available:

- `centralus`
- `eastus`
- `eastus2`
- `northcentralus`
- `southcentralus`
- `westus`
- `westus3`

Model, quota, and feature availability still varies by subscription and region, so validate Foundry IQ, Agent Service capabilities, and Azure OpenAI model availability before workshop day.

## Prerequisites

- Azure subscription with quota/permissions for Azure AI Search, Azure OpenAI, and Azure AI Foundry resources
- Azure Developer CLI (`azd`) installed
- Azure CLI (`az`) installed and logged in

## Deploy

```bash
azd auth login
azd init
azd env new workshop
azd up
```

`azd up` will:

- create (or use) one resource group for the environment
- deploy the Bicep template in `infra/main.bicep`

## Deploy without `azd`

If you cannot use `azd`, use one of the Cloud Shell scripts in `scripts/` after signing in with `az login`:

```bash
bash ./scripts/deploy-coffee-workshop.sh
```

```powershell
pwsh ./scripts/deploy-coffee-workshop.ps1
```

Each script will:

- prompt for a resource group name and Azure location
- create the resource group if needed
- deploy `infra/main.bicep` with `infra/main.parameters.json`
- upload the `data/Coffee/*` folders into matching blob containers

## Customize

Update `infra/main.parameters.json` for workshop-specific values:

- `location`
- `nameSuffix` (readable workshop label; the template appends a dynamic unique code automatically)
- model names/versions/capacity

## Notes

- OpenAI model/version support varies by region and subscription. If deployment fails, switch model version in `infra/main.parameters.json`.
- The template intentionally enables key access for services where requested.
