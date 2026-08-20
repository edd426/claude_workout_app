/**
 * Snapshot sync endpoints (issue #78) — wire contract v2.
 *
 * The phone (SwiftData) is authoritative; Azure is a read-mostly mirror for
 * MCP reads and disaster restore. There is no client-clock last-write-wins:
 * every push is the COMPLETE state of the four synced collections, and the
 * server reconciles each Cosmos container to match it exactly.
 *
 * POST /api/sync/snapshot
 *   Body: { schemaVersion: 2, snapshot: { workouts, templates,
 *           customExercises, bodyWeightEntries } }
 *   For each container: upsert every doc in the snapshot, then delete every
 *   doc whose id is not in the snapshot (deletions propagate — no
 *   tombstones). Idempotent: re-pushing the same snapshot converges to the
 *   same end state; the revision still increments (it counts pushes, it does
 *   not hash content). Individual operation failures do not abort the push —
 *   they are collected and reported with accurate counts in a 500 response;
 *   the client retries the full snapshot later and converges.
 *
 * GET /api/sync/snapshot
 *   Returns { revision, serverTime, snapshot } — the full current mirror,
 *   for disaster restore. revision/serverTime come from the metadata doc
 *   stamped by the last successful push.
 *
 * Revision metadata lives in the `syncMeta` container as the single doc
 * { id: "snapshot", revision, serverTime }. Chat, insights, and preferences
 * containers are NOT touched by snapshot sync (they remain on the legacy
 * push/pull path until removed).
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { Container } from "@azure/cosmos";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { readItemOrNull } from "../shared/readHelpers";
import {
  SUPPORTED_SNAPSHOT_SCHEMA_VERSIONS,
  SnapshotCollections,
  SnapshotContainerCounts,
  SnapshotCounts,
  SnapshotPushRequest,
  SnapshotPushResponse,
  SnapshotReadResponse,
  SyncMetaDoc,
} from "../shared/types";

/** Snapshot collection → Cosmos container mapping. */
interface SnapshotCollectionMapping {
  field: keyof SnapshotCollections;
  container: string;
}

const V2_COLLECTIONS: SnapshotCollectionMapping[] = [
  { field: "workouts", container: "workouts" },
  { field: "templates", container: "templates" },
  { field: "customExercises", container: "exercises" },
  { field: "bodyWeightEntries", container: "bodyWeightEntries" },
];

const V3_COLLECTIONS: SnapshotCollectionMapping[] = [
  ...V2_COLLECTIONS,
  { field: "exerciseReports", container: "exerciseReports" },
];

const V4_COLLECTIONS: SnapshotCollectionMapping[] = [
  ...V3_COLLECTIONS,
  { field: "exerciseOverlays", container: "exerciseOverlays" },
];

/**
 * Which collections a push of a given schemaVersion reconciles.
 *
 * A v2 client does not know reports exist, so its push must NOT be read as
 * "there are no reports" — that would delete the whole container on the next
 * sync from a phone still on the old build. Absent from the contract means
 * untouched, not empty. Only a v3 push reconciles `exerciseReports`.
 */
const SNAPSHOT_COLLECTIONS_BY_VERSION: Record<number, SnapshotCollectionMapping[]> = {
  2: V2_COLLECTIONS,
  3: V3_COLLECTIONS,
  4: V4_COLLECTIONS,
};

/** Every container a read/restore should return, regardless of push version. */
const SNAPSHOT_COLLECTIONS = V4_COLLECTIONS;

const SYNC_META_CONTAINER = "syncMeta";
const SYNC_META_ID = "snapshot";

/** Cosmos query page size. Pages are looped until exhausted — never a cap. */
const PAGE_SIZE = 100;

/** Cosmos system properties stripped from restore reads. */
const COSMOS_SYSTEM_PROPS = ["_rid", "_self", "_etag", "_attachments", "_ts"];

function badRequest(message: string): HttpResponseInit {
  return { status: 400, jsonBody: { error: message } };
}

function isCode404(err: unknown): boolean {
  const code = (err as { code?: number | string }).code;
  return code === 404 || code === "NotFound";
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  const code = (err as { code?: number | string }).code;
  return code !== undefined ? `code ${code}` : String(err);
}

/**
 * Validates the request body against wire contract v2. Returns an error
 * response, or null when the body is a well-formed full-state snapshot.
 * Validation runs BEFORE any write so a malformed push never half-applies.
 */
function validateBody(body: SnapshotPushRequest): HttpResponseInit | null {
  if (body === null || typeof body !== "object") {
    return badRequest("Malformed body: expected a JSON object");
  }
  const collections = SNAPSHOT_COLLECTIONS_BY_VERSION[body.schemaVersion];
  if (!collections) {
    return badRequest(
      `Unsupported schemaVersion: ${JSON.stringify(body.schemaVersion)}. ` +
        `Expected one of ${SUPPORTED_SNAPSHOT_SCHEMA_VERSIONS.join(", ")}.`
    );
  }
  const snapshot = body.snapshot;
  if (snapshot === null || typeof snapshot !== "object") {
    return badRequest("Malformed body: missing snapshot object");
  }
  for (const { field } of collections) {
    const docs = snapshot[field];
    if (!Array.isArray(docs)) {
      // A missing array is NOT treated as "empty" — an empty array is an
      // explicit full wipe of that collection; a missing one is a client bug.
      return badRequest(
        `Malformed snapshot: ${field} must be an array (the complete set, [] to wipe)`
      );
    }
    for (const doc of docs) {
      if (doc === null || typeof doc !== "object" || Array.isArray(doc)) {
        return badRequest(`Malformed snapshot: ${field} contains a non-object doc`);
      }
      const id = (doc as Record<string, unknown>)["id"];
      if (typeof id !== "string" || id.length === 0) {
        return badRequest(
          `Malformed snapshot: every ${field} doc must have a non-empty string id`
        );
      }
    }
  }
  return null;
}

/**
 * Queries all ids in a container, looping pages until exhausted. The
 * delete-absent reconciliation step must see EVERY existing id — a capped
 * scan would silently leave deleted records in the mirror.
 */
async function queryAllIds(container: Container): Promise<string[]> {
  const iterator = container.items.query(
    { query: "SELECT c.id FROM c" },
    { maxItemCount: PAGE_SIZE }
  );
  const ids: string[] = [];
  while (iterator.hasMoreResults()) {
    const { resources } = await iterator.fetchNext();
    for (const row of resources ?? []) {
      const id = (row as { id?: unknown }).id;
      if (typeof id === "string") ids.push(id);
    }
  }
  return ids;
}

/** Queries all docs in a container, looping pages until exhausted. */
async function queryAllDocs(
  container: Container
): Promise<Record<string, unknown>[]> {
  const iterator = container.items.query(
    { query: "SELECT * FROM c" },
    { maxItemCount: PAGE_SIZE }
  );
  const docs: Record<string, unknown>[] = [];
  while (iterator.hasMoreResults()) {
    const { resources } = await iterator.fetchNext();
    for (const doc of resources ?? []) {
      docs.push(doc as Record<string, unknown>);
    }
  }
  return docs;
}

function stripSystemProps(doc: Record<string, unknown>): Record<string, unknown> {
  const clean: Record<string, unknown> = { ...doc };
  for (const prop of COSMOS_SYSTEM_PROPS) {
    delete clean[prop];
  }
  return clean;
}

/**
 * Reconciles one Cosmos container to exactly the snapshot's doc set: upsert
 * everything in the snapshot, then delete everything absent from it. A
 * failed operation is recorded in `failures` and never aborts the rest.
 */
async function reconcileContainer(
  containerName: string,
  docs: Record<string, unknown>[],
  failures: string[]
): Promise<SnapshotContainerCounts> {
  const container = getDatabase().container(containerName);
  const counts: SnapshotContainerCounts = { upserted: 0, deleted: 0 };

  for (const doc of docs) {
    const id = doc["id"] as string;
    try {
      await container.items.upsert(doc);
      counts.upserted += 1;
    } catch (err) {
      failures.push(`upsert ${containerName}/${id}: ${errorMessage(err)}`);
    }
  }

  const snapshotIds = new Set(docs.map((doc) => doc["id"] as string));

  let existingIds: string[];
  try {
    existingIds = await queryAllIds(container);
  } catch (err) {
    // Without a complete scan the delete-absent step cannot run safely for
    // this container; report it and let the client's retry converge.
    failures.push(`scan ${containerName}: ${errorMessage(err)}`);
    return counts;
  }

  for (const id of existingIds) {
    if (snapshotIds.has(id)) continue;
    try {
      await container.item(id, id).delete();
      counts.deleted += 1;
    } catch (err) {
      if (isCode404(err)) {
        // Already gone (concurrent removal) — the end state converged.
        counts.deleted += 1;
      } else {
        failures.push(`delete ${containerName}/${id}: ${errorMessage(err)}`);
      }
    }
  }

  return counts;
}

app.http("syncSnapshotPush", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "sync/snapshot",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: SnapshotPushRequest;
    try {
      body = (await request.json()) as SnapshotPushRequest;
    } catch {
      return badRequest("Invalid JSON body");
    }

    const validationError = validateBody(body);
    if (validationError) return validationError;

    const failures: string[] = [];
    const counts = {} as SnapshotCounts;

    try {
      for (const { field, container } of SNAPSHOT_COLLECTIONS_BY_VERSION[
        body.schemaVersion
      ]) {
        counts[field] = await reconcileContainer(
          container,
          body.snapshot[field] ?? [],
          failures
        );
      }

      if (failures.length > 0) {
        // Revision is NOT advanced on a failed push — it counts successful
        // pushes. The client treats non-200 as failed and retries the full
        // snapshot; upserts and deletes are idempotent, so the retry converges.
        context.error("Snapshot push incomplete:", failures);
        return {
          status: 500,
          jsonBody: {
            error: `Snapshot push incomplete: ${failures.length} operation(s) failed`,
            failures,
            counts,
          },
        };
      }

      // Single-writer by design (one phone); a plain read-increment-write of
      // the metadata doc is sufficient — no optimistic concurrency needed.
      const metaContainer = getDatabase().container(SYNC_META_CONTAINER);
      const existingMeta = await readItemOrNull<SyncMetaDoc>(
        metaContainer,
        SYNC_META_ID
      );
      const revision = (existingMeta?.revision ?? 0) + 1;
      const serverTime = new Date().toISOString();
      const meta: SyncMetaDoc = { id: SYNC_META_ID, revision, serverTime };
      await metaContainer.items.upsert(meta);

      const response: SnapshotPushResponse = { revision, serverTime, counts };
      return { jsonBody: response };
    } catch (error) {
      context.error("Snapshot push failed:", error);
      return {
        status: 500,
        jsonBody: { error: "Failed to apply snapshot", counts },
      };
    }
  },
});

app.http("syncSnapshotGet", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "sync/snapshot",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    try {
      const metaContainer = getDatabase().container(SYNC_META_CONTAINER);
      const meta = await readItemOrNull<SyncMetaDoc>(metaContainer, SYNC_META_ID);

      const snapshot = {} as SnapshotCollections;
      for (const { field, container } of SNAPSHOT_COLLECTIONS) {
        const docs = await queryAllDocs(getDatabase().container(container));
        snapshot[field] = docs.map(stripSystemProps);
      }

      const response: SnapshotReadResponse = {
        // Revision 0 = nothing has ever been pushed (fresh mirror).
        revision: meta?.revision ?? 0,
        serverTime: meta?.serverTime ?? new Date().toISOString(),
        snapshot,
      };
      return { jsonBody: response };
    } catch (error) {
      context.error("Snapshot read failed:", error);
      return { status: 500, jsonBody: { error: "Failed to read snapshot" } };
    }
  },
});
