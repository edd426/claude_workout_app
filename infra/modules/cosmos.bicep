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
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
    options: {
      autoscaleSettings: {
        maxThroughput: 1000
      }
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
  {
    name: 'preferences'
    partitionKeyPath: '/id'
  }
]

// Containers intentionally omit `options.throughput` and `options.autoscaleSettings`.
// Throughput is provisioned at the database level (see `database` resource above) and
// shared across all containers. This keeps total RU/s at the 1,000 RU/s free-tier credit.
// Adding per-container throughput here will trigger a deployment failure ("cannot
// configure throughput at both database and container level") and, if it succeeded,
// would push billable RU/s over the free tier — see AZURE_COST_REPORT_2026-05.md.
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
