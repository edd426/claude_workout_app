import { CosmosClient, Database } from "@azure/cosmos";

let client: CosmosClient | null = null;
let database: Database | null = null;

const DATABASE_NAME = "workout-db";

export function getCosmosClient(): CosmosClient {
  if (!client) {
    const connectionString = process.env.COSMOS_CONNECTION_STRING;
    if (!connectionString) {
      throw new Error("COSMOS_CONNECTION_STRING not configured");
    }
    client = new CosmosClient(connectionString);
  }
  return client;
}

export function getDatabase(): Database {
  if (!database) {
    database = getCosmosClient().database(DATABASE_NAME);
  }
  return database;
}
