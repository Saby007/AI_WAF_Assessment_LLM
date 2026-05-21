// provision-demo.bicep
// Provisions sample AI workloads to populate the empty charts in the AI WAF workbook.
// Creates: AI Search (Basic), Azure OpenAI account + gpt-4o-mini deployment,
// Azure ML workspace + tiny AmlCompute cluster, and supporting Storage/KV/Log Analytics.

@description('Suffix appended to globally-unique resource names. Letters+digits only.')
param suffix string

@description('Primary region for AI Search and Azure ML resources.')
param location string = resourceGroup().location

// ----- Names -----
var searchName    = 'srch-wafdemo-${suffix}'
var mlwsName      = 'mlw-wafdemo-${suffix}'
var saName        = take('sawafdemo${suffix}', 24)
var kvName        = take('kv-wafdemo-${suffix}', 24)
var lawName       = 'law-wafdemo-${suffix}'
var aiName        = 'appi-wafdemo-${suffix}'

// =============== AI Search ===============
resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchName
  location: location
  sku: {
    name: 'basic'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'enabled'
    disableLocalAuth: false
    semanticSearch: 'free'
  }
  tags: {
    Owner: 'ssamadda'
    Purpose: 'ai-waf-workbook-demo'
  }
}

// =============== ML workspace dependencies ===============
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: saName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: null
  }
}

// =============== Azure ML workspace ===============
resource mlws 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: mlwsName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI WAF Demo Workspace'
    storageAccount: storage.id
    keyVault: kv.id
    applicationInsights: appi.id
    publicNetworkAccess: 'Enabled'
    hbiWorkspace: false
  }
  tags: {
    Owner: 'ssamadda'
    Purpose: 'ai-waf-workbook-demo'
  }
}

resource cpuCluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  parent: mlws
  name: 'cpu-cluster'
  location: location
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: 'STANDARD_D2DS_V5'
      vmPriority: 'Dedicated'
      scaleSettings: {
        minNodeCount: 0
        maxNodeCount: 1
        nodeIdleTimeBeforeScaleDown: 'PT120S'
      }
    }
  }
}

// ----- Outputs -----
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output mlWorkspaceId  string = mlws.id
output cpuClusterName string = cpuCluster.name
