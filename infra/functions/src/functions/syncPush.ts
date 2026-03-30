import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { SyncPushRequest, SyncPushResponse } from "../shared/types";

const VALID_COLLECTIONS = [
  "workouts",
  "templates",
  "chat",
  "insights",
  "preferences",
];

interface UpsertResult {
  accepted: number;
  conflicts: number;
}

async function upsertToContainer(
  containerName: string,
  records: Record<string, unknown>[]
): Promise<UpsertResult> {
  const database = getDatabase();
  const container = database.container(containerName);
  let accepted = 0;
  let conflicts = 0;

  for (const record of records) {
    const id = record["id"] as string;
    if (!id) {
      conflicts++;
      continue;
    }

    try {
      // Try to read the existing document
      const { resource: existing } = await container.item(id, id).read();

      if (existing) {
        const existingModified = existing["lastModified"] as string | undefined;
        const incomingModified = record["lastModified"] as string | undefined;

        // Last-write-wins: only overwrite if incoming is newer
        if (
          existingModified &&
          incomingModified &&
          incomingModified <= existingModified
        ) {
          conflicts++;
          continue;
        }
      }
    } catch {
      // Document doesn't exist yet — proceed with upsert
    }

    try {
      await container.items.upsert(record);
      accepted++;
    } catch {
      conflicts++;
    }
  }

  return { accepted, conflicts };
}

app.http("syncPush", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "sync/push",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: SyncPushRequest;
    try {
      body = (await request.json()) as SyncPushRequest;
    } catch {
      return {
        status: 400,
        jsonBody: { error: "Invalid JSON body" },
      };
    }

    try {
      let totalAccepted = 0;
      let totalConflicts = 0;

      for (const collection of VALID_COLLECTIONS) {
        const records = body[collection as keyof SyncPushRequest];
        if (records && records.length > 0) {
          const result = await upsertToContainer(collection, records);
          totalAccepted += result.accepted;
          totalConflicts += result.conflicts;
        }
      }

      const response: SyncPushResponse = {
        accepted: totalAccepted,
        conflicts: totalConflicts,
        serverTimestamp: new Date().toISOString(),
      };

      return { jsonBody: response };
    } catch (error) {
      context.error("Sync push failed:", error);
      return {
        status: 500,
        jsonBody: { error: "Failed to push sync data" },
      };
    }
  },
});
