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
    // Both of these already hold on the live account. They are declared here
    // because they were not, and `what-if` therefore proposed turning them
    // OFF on any deployment — silently weakening TLS and disabling failover
    // as a side effect of adding a container (#140).
    minimalTlsVersion: 'Tls12'
    enableAutomaticFailover: true
    backupPolicy: {
      type: 'Periodic'
      // Two backup copies are free; copies = retention / interval, so keep the
      // ratio at exactly 2. Daily + 48h beats the old 4h + 8h: a data-loss
      // incident is rarely noticed within 8 hours (issue #73).
      periodicModeProperties: {
        backupIntervalInMinutes: 1440
        backupRetentionIntervalInHours: 48
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
  // Snapshot sync (issue #78): body-weight entries mirrored from the phone.
  {
    name: 'bodyWeightEntries'
    partitionKeyPath: '/id'
  }
  // Snapshot sync (issue #78): single metadata doc { id: 'snapshot',
  // revision, serverTime } — server-assigned revision counter.
  {
    name: 'syncMeta'
    partitionKeyPath: '/id'
  }
  // Snapshot sync (issue #135): user-filed exercise/app reports, mirrored
  // from the phone so the MCP server can read the complaint backlog.
  {
    name: 'exerciseReports'
    partitionKeyPath: '/id'
  }
  // Snapshot sync (issue #140): user data added to *bundled* exercises —
  // notes and photos. Keyed by the free-exercise-db `externalId`, not the
  // local UUID, because a reinstall mints new UUIDs for the same exercise.
  // Deliberately its own container rather than a `kind` discriminator inside
  // `exercises`: reconcileContainer deletes every doc absent from the
  // snapshot, so two doc kinds sharing a container means each push wipes the
  // other unless every read remembers to union them first.
  {
    name: 'exerciseOverlays'
    partitionKeyPath: '/id'
  }
  // MCP write path (issue #88): durable operations drained by the phone.
  // Deliberately separate from the snapshot-reconciled containers.
  {
    name: 'inbox'
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
