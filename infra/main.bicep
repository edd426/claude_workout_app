targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = 'westeurope'

@description('Cosmos DB account name')
param cosmosAccountName string = 'cosmos-workout-prod'

@description('Cosmos DB database name')
param cosmosDatabaseName string = 'workout-db'

@description('Storage account name')
param storageAccountName string = 'stworkoutprod'

@description('Function App name')
param functionAppName string = 'func-workout-prod'

@description('App Insights name')
param appInsightsName string = 'ai-workout-prod'

@description('API key for authenticating iOS app requests')
@secure()
param apiKey string

@description('Anthropic API key for chat proxy')
@secure()
param anthropicApiKey string

@description('Default Anthropic model')
param anthropicModelDefault string = 'claude-haiku-4-5-20251001'

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos-deployment'
  params: {
    location: location
    accountName: cosmosAccountName
    databaseName: cosmosDatabaseName
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: storageAccountName
  }
}

module functions 'modules/functions.bicep' = {
  name: 'functions-deployment'
  params: {
    location: location
    functionAppName: functionAppName
    appInsightsName: appInsightsName
    storageConnectionString: storage.outputs.connectionString
    cosmosConnectionString: cosmos.outputs.connectionString
    apiKey: apiKey
    anthropicApiKey: anthropicApiKey
    anthropicModelDefault: anthropicModelDefault
  }
}

output cosmosEndpoint string = cosmos.outputs.endpoint
output storageBlobEndpoint string = storage.outputs.blobEndpoint
output functionAppUrl string = functions.outputs.functionAppUrl
