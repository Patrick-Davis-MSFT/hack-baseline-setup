targetScope = 'resourceGroup'

@description('Region for all resources. Inherited from the resource group created by azd. Supported US regions: centralus, eastus, eastus2, northcentralus, southcentralus, westus, westus3.')
param location string = resourceGroup().location

@description('A short readable suffix for naming. Lowercase letters and numbers only (3-8 chars). A dynamic uniqueness code is added automatically.')
@minLength(3)
@maxLength(8)
param nameSuffix string = substring(toLower(uniqueString(subscription().subscriptionId, resourceGroup().id)), 0, 8)

@description('Azure AI Search SKU.')
@allowed([
  'standard'
])
param searchSku string = 'standard'

var uniqueCode = substring(toLower(uniqueString(subscription().subscriptionId, resourceGroup().name, location)), 0, 5)
var storageAccountName = 'st${nameSuffix}${uniqueCode}'
var searchServiceName = 'srch-${nameSuffix}-${uniqueCode}'
var appInsightsName = 'appi-${nameSuffix}-${uniqueCode}'
var keyVaultName = 'kv-${nameSuffix}-${uniqueCode}'
var foundryHubName = 'hub-${nameSuffix}-${uniqueCode}'
var foundryProjectName = 'proj-${nameSuffix}-${uniqueCode}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2026-04-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    isVersioningEnabled: true
  }
}

resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: searchSku
  }
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    authOptions: {
      apiKeyOnly: {}
    }
    disableLocalAuth: false
    hostingMode: 'Default'
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: false
    IngestionMode: 'ApplicationInsights'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    Request_Source: 'rest'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
  }
}


resource foundryHub 'Microsoft.MachineLearningServices/workspaces@2025-12-01' = {
  name: foundryHubName
  location: location
  kind: 'hub'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    friendlyName: 'Foundry Hub ${nameSuffix}'
    description: 'Hub for Foundry IQ and Agent Workflow workshop'
    applicationInsights: applicationInsights.id
    keyVault: keyVault.id
    storageAccount: storageAccount.id
  }
}

resource foundryHubSearchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2025-12-01' = {
  parent: foundryHub
  name: 'search'
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchService.name}.search.windows.net'
    authType: 'ApiKey'
    isSharedToAll: true
    useWorkspaceManagedIdentity: false
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
    }
    credentials: {
      key: searchService.listAdminKeys().primaryKey
    }
  }
}

resource foundryProject 'Microsoft.MachineLearningServices/workspaces@2025-12-01' = {
  name: foundryProjectName
  location: location
  kind: 'project'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  tags: {
    SecurityControl: 'Ignore'
  }
  properties: {
    friendlyName: 'Foundry Project ${nameSuffix}'
    description: 'Project for Foundry IQ and Agent Workflow workshop'
    hubResourceId: foundryHub.id
    publicNetworkAccess: 'Enabled'
    allowPublicAccessWhenBehindVnet: true
  }
}

output location string = location
output storageAccountName string = storageAccount.name
output searchServiceName string = searchService.name
output applicationInsightsName string = applicationInsights.name
output keyVaultName string = keyVault.name
output foundryHubName string = foundryHub.name
output foundryProjectName string = foundryProject.name
