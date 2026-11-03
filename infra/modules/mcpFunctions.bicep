// Remote MCP server for the claude.ai connector — issue #162.
//
// A Function App of its own (not part of func-workout-prod, the phone's API)
// built from infra/mcp. It reaches workout data only through the Functions API
// with the shared API key, exactly like the local stdio server.
//
// Deploy this module ON ITS OWN, never through main.bicep:
//
//   az deployment group create -g rg-workout-app-prod \
//     --template-file infra/modules/mcpFunctions.bicep \
//     --parameters functionsApiKey=... entraTenantId=... entraClientId=... \
//                  entraClientSecret=... allowedOids=...
//
// Runbook: infra/mcp/scripts/deploy-remote.sh reads every secret from Azure or
// the macOS Keychain and never prints one.
//
// Unlike modules/functions.bicep, redeploying this template does not undeploy
// the code: on Flex Consumption the package lives in the app-package blob
// container, not in a WEBSITE_RUN_FROM_PACKAGE setting. appSettings below are
// still wholesale, so any setting added by hand outside this file is dropped.

@description('Location for all resources')
param location string = resourceGroup().location

@description('Function App name; also fixes the public base URL')
param functionAppName string = 'func-workout-mcp-prod'

@description('Dedicated storage account for the Function App runtime')
param storageAccountName string = 'stwkmcp${uniqueString(resourceGroup().id)}'

@description('Existing Application Insights component to log into')
param appInsightsName string = 'ai-workout-prod'

@description('Base URL of the workout Functions API (no /api suffix)')
param functionsBaseUrl string = 'https://func-workout-prod.azurewebsites.net'

@description('Shared API key of the workout Functions API')
@secure()
param functionsApiKey string

@description('Entra tenant id')
param entraTenantId string

@description('Client id of the "ClaudeLifter Workout MCP" Entra app')
param entraClientId string

@description('Client secret of that Entra app')
@secure()
param entraClientSecret string

@description('Comma-separated Entra object ids allowed to call /mcp; empty admits nobody')
param allowedOids string

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'

var deploymentContainerName = 'app-package'

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

// Flex Consumption: Azure refuses new Linux Consumption (Y1) apps in this
// resource group ("Dynamic SKU, Linux Worker not available"), 2026-11-02.
resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${functionAppName}-plan'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  dependsOn: [
    deploymentContainer
  ]
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 512
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConnectionString }
        { name: 'DEPLOYMENT_STORAGE_CONNECTION_STRING', value: storageConnectionString }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'PUBLIC_BASE_URL', value: 'https://${functionAppName}.azurewebsites.net' }
        { name: 'FUNCTIONS_BASE_URL', value: functionsBaseUrl }
        { name: 'FUNCTIONS_API_KEY', value: functionsApiKey }
        { name: 'ENTRA_TENANT_ID', value: entraTenantId }
        { name: 'ENTRA_CLIENT_ID', value: entraClientId }
        { name: 'ENTRA_CLIENT_SECRET', value: entraClientSecret }
        { name: 'ALLOWED_OIDS', value: allowedOids }
      ]
    }
  }
}

// No FTP. Deployment goes through `func azure functionapp publish`.
resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
  parent: functionApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

output functionAppName string = functionApp.name
output publicBaseUrl string = 'https://${functionApp.properties.defaultHostName}'
