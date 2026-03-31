import { CosmosClient, Database, Container } from "@azure/cosmos";
import { DefaultAzureCredential } from "@azure/identity";

let client: CosmosClient | null = null;
let database: Database | null = null;

export function getCosmosClient(): CosmosClient {
  if (!client) {
    const endpoint = process.env.COSMOS_DB_ENDPOINT;
    if (!endpoint) {
      throw new Error("COSMOS_DB_ENDPOINT environment variable not configured");
    }
    const credential = new DefaultAzureCredential();
    client = new CosmosClient({ endpoint, aadCredentials: credential });
  }
  return client;
}

export function getDatabase(): Database {
  if (!database) {
    const dbName = process.env.COSMOS_DB_DATABASE || "workout-db";
    database = getCosmosClient().database(dbName);
  }
  return database;
}

export function getContainer(name: string): Container {
  return getDatabase().container(name);
}
