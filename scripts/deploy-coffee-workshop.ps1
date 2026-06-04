#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$templateFile = Join-Path $repoRoot 'infra/main.bicep'
$parametersFile = Join-Path $repoRoot 'infra/main.parameters.json'
$coffeeRoot = Join-Path $repoRoot 'data/Coffee'

function Require-Command {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Prompt-Value {
    param(
        [Parameter(Mandatory)]
        [string]$Label,
        [string]$DefaultValue
    )

    while ($true) {
        $prompt = if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
            "$Label"
        }
        else {
            "$Label [$DefaultValue]"
        }

        $value = Read-Host -Prompt $prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($DefaultValue)) {
            return $DefaultValue
        }
    }
}

function Ensure-LoggedIn {
    az account show | Out-Null
}

function Ensure-ResourceGroup {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$Location
    )

    $exists = az group exists --name $ResourceGroup -o tsv
    if ($exists -eq 'true') {
        $existingLocation = az group show --name $ResourceGroup --query location -o tsv
        if ($existingLocation -ne $Location) {
            throw "Resource group '$ResourceGroup' already exists in '$existingLocation', not '$Location'."
        }

        Write-Host "Using existing resource group $ResourceGroup in $existingLocation"
        return
    }

    Write-Host "Creating resource group $ResourceGroup in $Location"
    az group create --name $ResourceGroup --location $Location --output none | Out-Null
}

function Deploy-Infrastructure {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$Location
    )

    Write-Host 'Deploying infrastructure from infra/main.bicep'
    az deployment group create `
        --resource-group $ResourceGroup `
        --template-file $templateFile `
        --parameters "@$parametersFile" location=$Location `
        --query properties.outputs `
        -o json | ConvertFrom-Json
}

function Upload-CoffeeDocs {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroup,
        [Parameter(Mandatory)]
        [string]$StorageAccountName
    )

    $storageAccountKey = az storage account keys list `
        --resource-group $ResourceGroup `
        --account-name $StorageAccountName `
        --query '[0].value' `
        -o tsv

    if ([string]::IsNullOrWhiteSpace($storageAccountKey)) {
        throw "Failed to retrieve a storage account key for $StorageAccountName."
    }

    Get-ChildItem -Path $coffeeRoot -Directory | ForEach-Object {
        $containerName = $_.Name.ToLowerInvariant()

        Write-Host "Uploading $($_.Name) to container $containerName"
        az storage container create `
            --name $containerName `
            --account-name $StorageAccountName `
            --account-key $storageAccountKey `
            --auth-mode key `
            --only-show-errors `
            --output none | Out-Null

        az storage blob upload-batch `
            --account-name $StorageAccountName `
            --account-key $storageAccountKey `
            --auth-mode key `
            --destination $containerName `
            --source $_.FullName `
            --overwrite true `
            --only-show-errors `
            --output none | Out-Null
    }
}

Require-Command -Name az

if (-not (Test-Path -Path $templateFile -PathType Leaf)) {
    throw "Template file not found: $templateFile"
}

if (-not (Test-Path -Path $parametersFile -PathType Leaf)) {
    throw "Parameters file not found: $parametersFile"
}

if (-not (Test-Path -Path $coffeeRoot -PathType Container)) {
    throw "Coffee source folder not found: $coffeeRoot"
}

Ensure-LoggedIn

$resourceGroup = Prompt-Value -Label 'Azure resource group name'
$location = Prompt-Value -Label 'Azure location' -DefaultValue 'eastus2'

Ensure-ResourceGroup -ResourceGroup $resourceGroup -Location $location
$deploymentOutputs = Deploy-Infrastructure -ResourceGroup $resourceGroup -Location $location
$storageAccountName = $deploymentOutputs.storageAccountName.value

if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
    throw 'Deployment completed, but the storage account output was not returned.'
}

Upload-CoffeeDocs -ResourceGroup $resourceGroup -StorageAccountName $storageAccountName

Write-Host ''
Write-Host 'Deployment complete'
Write-Host "Resource group: $resourceGroup"
Write-Host "Location: $location"
Write-Host "Storage account: $storageAccountName"