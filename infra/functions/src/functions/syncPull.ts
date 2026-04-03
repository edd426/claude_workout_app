import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { SyncPullRequest, SyncPullResponse } from "../shared/types";

const VALID_COLLECTIONS = [
  "workouts",
  "templates",
  "chat",
  "insights",
  "preferences",
];

async function pullFromContainer(
  containerName: string,
  lastSyncTimestamp: string
): Promise<Record<string, unknown>[]> {
  const database = getDatabase();
  const container = database.container(containerName);

  const query = {
    query: "SELECT * FROM c WHERE c.lastModified > @lastSync",
    parameters: [{ name: "@lastSync", value: lastSyncTimestamp }],
  };

  const { resources } = await container.items.query(query).fetchAll();
  return resources;
}

app.http("syncPull", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "sync/pull",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: SyncPullRequest;
    try {
      body = (await request.json()) as SyncPullRequest;
    } catch {
      return {
        status: 400,
        jsonBody: { error: "Invalid JSON body" },
      };
    }

    if (!body.collections) {
      return {
        status: 400,
        jsonBody: {
          error: "Missing required field: collections",
        },
      };
    }

    // Default to epoch on first-ever sync (iOS client sends null/undefined)
    const lastSync = body.lastSyncTimestamp || "1970-01-01T00:00:00.000Z";

    const requestedCollections = body.collections.filter((c) =>
      VALID_COLLECTIONS.includes(c)
    );

    try {
      const results: Record<string, Record<string, unknown>[]> = {};
      await Promise.all(
        requestedCollections.map(async (collection) => {
          results[collection] = await pullFromContainer(
            collection,
            lastSync
          );
        })
      );

      const response: SyncPullResponse = {
        workouts: results["workouts"] ?? [],
        templates: results["templates"] ?? [],
        chat: results["chat"] ?? [],
        insights: results["insights"] ?? [],
        preferences: results["preferences"] ?? [],
        serverTimestamp: new Date().toISOString(),
      };

      return { jsonBody: response };
    } catch (error) {
      context.error("Sync pull failed:", error);
      return {
        status: 500,
        jsonBody: { error: "Failed to pull sync data" },
      };
    }
  },
});
