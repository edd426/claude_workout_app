@description('Location for all resources')
param location string

@description('Function App name')
param functionAppName string

@description('App Insights name')
param appInsightsName string

@description('Storage account connection string for Function App')
@secure()
param storageConnectionString string

@description('Cosmos DB connection string')
@secure()
param cosmosConnectionString string

@description('API key for authenticating iOS app requests')
@secure()
param apiKey string

@description('Anthropic API key for chat proxy')
@secure()
param anthropicApiKey string

@description('Default Anthropic model')
param anthropicModelDefault string = 'claude-haiku-4-5-20251001'

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 90
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|20'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'COSMOS_CONNECTION_STRING'
          value: cosmosConnectionString
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: storageConnectionString
        }
        {
          name: 'ANTHROPIC_API_KEY'
          value: anthropicApiKey
        }
        {
          name: 'API_KEY'
          value: apiKey
        }
        {
          name: 'ANTHROPIC_MODEL_DEFAULT'
          value: anthropicModelDefault
        }
      ]
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
  }
}

@description('Function App default hostname')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('App Insights instrumentation key')
output appInsightsKey string = appInsights.properties.InstrumentationKey
