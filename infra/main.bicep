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
var foundryHubName = 'hub-${nameSuffix}-${uniqueCode}'
var foundryProjectName = 'proj-${nameSuffix}-${uniqueCode}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
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

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: true
  }
}

resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
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
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    semanticSearch: 'free'
  }
}


resource foundryHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
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
    publicNetworkAccess: 'Enabled'
    keyVault: null
    storageAccount: storageAccount.id
  }
}

resource foundryProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
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
  }
}

output location string = location
output storageAccountName string = storageAccount.name
output searchServiceName string = searchService.name
output foundryHubName string = foundryHub.name
output foundryProjectName string = foundryProject.name
