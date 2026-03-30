@description('Location for all resources')
param location string

@description('Cosmos DB account name')
param accountName string

@description('Database name')
param databaseName string

@description('Enable free tier')
param enableFreeTier bool = true

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: enableFreeTier
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: []
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

var containers = [
  {
    name: 'exercises'
    partitionKeyPath: '/id'
  }
  {
    name: 'templates'
    partitionKeyPath: '/id'
  }
  {
    name: 'workouts'
    partitionKeyPath: '/id'
  }
  {
    name: 'chat'
    partitionKeyPath: '/workoutId'
  }
  {
    name: 'insights'
    partitionKeyPath: '/id'
  }
]

resource cosmosContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = [
  for container in containers: {
    parent: database
    name: container.name
    properties: {
      resource: {
        id: container.name
        partitionKey: {
          paths: [container.partitionKeyPath]
          kind: 'Hash'
        }
      }
    }
  }
]

@description('Cosmos DB connection string')
output connectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString

@description('Cosmos DB endpoint')
output endpoint string = cosmosAccount.properties.documentEndpoint
