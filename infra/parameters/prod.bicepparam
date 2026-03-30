using '../main.bicep'

param location = 'westeurope'
param cosmosAccountName = 'cosmos-workout-prod'
param cosmosDatabaseName = 'workout-db'
param storageAccountName = 'stworkoutprod'
param functionAppName = 'func-workout-prod'
param appInsightsName = 'ai-workout-prod'
param anthropicModelDefault = 'claude-haiku-4-5-20251001'

// Secrets — supply at deploy time:
//   az deployment group create \
//     --resource-group rg-workout-app-prod \
//     --template-file main.bicep \
//     --parameters @parameters/prod.bicepparam \
//     --parameters apiKey='<value>' anthropicApiKey='<value>'
