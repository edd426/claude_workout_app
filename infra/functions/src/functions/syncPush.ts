/**
 * DEPRECATED (issue #78): bidirectional last-write-wins sync is replaced by
 * the one-way snapshot mirror — POST/GET /api/sync/snapshot (syncSnapshot.ts).
 * This endpoint is kept fully intact ONLY because the currently installed
 * phone build still calls it; remove it once that build is reinstalled with
 * the snapshot-sync client. Do not extend it.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import {
  SyncPushRequest,
  SyncPushResponse,
  SyncPushRecordResult,
} from "../shared/types";

const VALID_COLLECTIONS = [
  "workouts",
  "templates",
  "chat",
  "insights",
  "preferences",
];

async function upsertToContainer(
  containerName: string,
  records: Record<string, unknown>[]
): Promise<SyncPushRecordResult[]> {
  const database = getDatabase();
  const container = database.container(containerName);
  const results: SyncPushRecordResult[] = [];

  for (const record of records) {
    const id = record["id"] as string;
    if (!id) {
      // Validation failure — surfaced as an error, never counted as a conflict.
      results.push({ id: id ?? "", collection: containerName, status: "error" });
      continue;
    }

    // Last-write-wins check. Only a confirmed 404 means "new record"; any
    // other read failure (throttling, timeout, auth, outage) must NOT fall
    // through to upsert — that would overwrite a possibly-newer server copy
    // without the LWW comparison ever running.
    let staleConflict = false;
    try {
      const { resource: existing } = await container.item(id, id).read();

      if (existing) {
        const existingModified = existing["lastModified"] as string | undefined;
        const incomingModified = record["lastModified"] as string | undefined;

        if (
          existingModified &&
          incomingModified &&
          incomingModified <= existingModified
        ) {
          staleConflict = true;
        }
      }
    } catch (err) {
      const code = (err as { code?: number | string }).code;
      if (code === 404 || code === "NotFound") {
        // Document doesn't exist yet — proceed with upsert.
      } else {
        results.push({ id, collection: containerName, status: "error" });
        continue;
      }
    }

    if (staleConflict) {
      // Incoming record lost LWW — existing server copy is kept, not written.
      results.push({ id, collection: containerName, status: "conflict" });
      continue;
    }

    try {
      await container.items.upsert(record);
      results.push({ id, collection: containerName, status: "accepted" });
    } catch {
      // Upsert threw — do NOT report this as synced (previously folded into conflicts).
      results.push({ id, collection: containerName, status: "error" });
    }
  }

  return results;
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
      const results: SyncPushRecordResult[] = [];

      for (const collection of VALID_COLLECTIONS) {
        const records = body[collection as keyof SyncPushRequest];
        if (records && records.length > 0) {
          results.push(...(await upsertToContainer(collection, records)));
        }
      }

      const response: SyncPushResponse = {
        accepted: results.filter((r) => r.status === "accepted").length,
        conflicts: results.filter((r) => r.status === "conflict").length,
        serverTimestamp: new Date().toISOString(),
        results,
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
