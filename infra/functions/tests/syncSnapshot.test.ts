/**
 * Tests for snapshot sync endpoints — issue #78
 *
 * The phone (SwiftData) is authoritative; Azure is a read-mostly mirror.
 * POST /api/sync/snapshot — full-state replace with reconciliation:
 *   upsert every doc in the snapshot, delete every doc not in it.
 *   Server assigns a monotonically increasing revision (counts pushes).
 * GET  /api/sync/snapshot — full current mirror for disaster restore.
 *
 * Wire contract v2:
 *   POST body: { schemaVersion: 2, snapshot: { workouts, templates,
 *                customExercises, bodyWeightEntries } }
 *   POST 200:  { revision, serverTime, counts: { <collection>: { upserted, deleted } } }
 *   GET 200:   { revision, serverTime, snapshot: { same four arrays } }
 *
 * Container mapping: workouts→workouts, templates→templates,
 * customExercises→exercises, bodyWeightEntries→bodyWeightEntries.
 * Revision metadata: doc id "snapshot" in the `syncMeta` container.
 * Chat, insights, preferences containers are NOT touched.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import { mockDatabase } from "./__mocks__/cosmos";
import "../src/functions/syncSnapshot";

const mockApp = app as unknown as { http: jest.Mock };
const mockAuthenticate = authenticate as jest.Mock;

type Doc = Record<string, unknown>;

interface CountsBody {
  workouts: { upserted: number; deleted: number };
  templates: { upserted: number; deleted: number };
  customExercises: { upserted: number; deleted: number };
  bodyWeightEntries: { upserted: number; deleted: number };
}

interface PushResponseBody {
  revision: number;
  serverTime: string;
  counts: CountsBody;
}

interface ReadResponseBody {
  revision: number;
  serverTime: string;
  snapshot: {
    workouts: Doc[];
    templates: Doc[];
    customExercises: Doc[];
    bodyWeightEntries: Doc[];
  };
}

type Handler = (
  req: unknown,
  ctx: InvocationContext
) => Promise<{ status?: number; jsonBody?: unknown }>;

function findHandler(name: string): Handler {
  const call = mockApp.http.mock.calls.find(([n]: [string]) => n === name);
  if (!call) throw new Error(`${name} handler was not registered with app.http()`);
  return call[1].handler;
}

function findRegistration(name: string): Record<string, unknown> {
  const call = mockApp.http.mock.calls.find(([n]: [string]) => n === name);
  if (!call) throw new Error(`${name} was not registered with app.http()`);
  return call[1];
}

function makeRequest(body?: unknown) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(body, { "x-api-key": "test-key" });
}

function isOk(status?: number) {
  // Azure Functions treats an undefined status as 200.
  return status === undefined || status === 200;
}

// ─── In-memory fake Cosmos containers ────────────────────────────────────────
// The shared cosmos mock returns one container for every name; snapshot
// reconciliation needs per-container state, paginated queries, and deletes,
// so this file installs its own fakes via mockDatabase.container.

function chunk<T>(items: T[], size: number): T[][] {
  const pages: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    pages.push(items.slice(i, i + size));
  }
  return pages;
}

class FakeContainer {
  docs = new Map<string, Doc>();
  /** Force the reconciliation/read query to emit pages of this size. */
  pageSize = 2;
  failUpsertIds = new Set<string>();
  failDeleteIds = new Set<string>();
  /** Ids the scan returns but whose delete throws 404 (concurrently gone). */
  vanishOnDeleteIds = new Set<string>();
  failQuery = false;

  readonly query = jest.fn((querySpec: { query: string }) => {
    if (this.failQuery) {
      return {
        hasMoreResults: () => true,
        fetchNext: async () => {
          throw new Error("query failed");
        },
        fetchAll: async () => {
          throw new Error("query failed");
        },
      };
    }
    const all = [...this.docs.values()];
    const idsOnly = /SELECT\s+(VALUE\s+)?c\.id\b/i.test(querySpec.query);
    const results = idsOnly ? all.map((d) => ({ id: d["id"] })) : all;
    const pages = chunk(results, this.pageSize);
    let index = 0;
    return {
      hasMoreResults: () => index < pages.length,
      fetchNext: async () => ({ resources: pages[index++] ?? [] }),
      fetchAll: async () => ({ resources: results }),
    };
  });

  readonly upsert = jest.fn(async (doc: Doc) => {
    const id = doc["id"] as string;
    if (this.failUpsertIds.has(id)) throw new Error(`upsert failed for ${id}`);
    this.docs.set(id, doc);
    return { resource: doc };
  });

  readonly deleteFn = jest.fn(async (id: string) => {
    if (this.failDeleteIds.has(id)) throw { code: 500 };
    if (this.vanishOnDeleteIds.has(id) || !this.docs.has(id)) throw { code: 404 };
    this.docs.delete(id);
    return {};
  });

  readonly readFn = jest.fn(async (id: string) => ({
    resource: this.docs.get(id),
  }));

  readonly items = { query: this.query, upsert: this.upsert };

  readonly item = jest.fn((id: string, _pk: string) => ({
    read: () => this.readFn(id),
    delete: () => this.deleteFn(id),
  }));

  ids(): string[] {
    return [...this.docs.keys()].sort();
  }

  seed(...docs: Doc[]) {
    for (const doc of docs) this.docs.set(doc["id"] as string, doc);
  }
}

let containers: Record<string, FakeContainer>;
let requestedContainerNames: string[];

beforeEach(() => {
  containers = {};
  requestedContainerNames = [];
  mockDatabase.container.mockReset();
  mockDatabase.container.mockImplementation((name: string) => {
    requestedContainerNames.push(name);
    if (!containers[name]) containers[name] = new FakeContainer();
    return containers[name];
  });
  mockAuthenticate.mockReturnValue(null);
});

function container(name: string): FakeContainer {
  if (!containers[name]) containers[name] = new FakeContainer();
  return containers[name];
}

function seedMeta(revision: number, serverTime = "2026-07-01T00:00:00.000Z") {
  container("syncMeta").seed({ id: "snapshot", revision, serverTime });
}

function emptySnapshot() {
  return {
    workouts: [] as Doc[],
    templates: [] as Doc[],
    customExercises: [] as Doc[],
    bodyWeightEntries: [] as Doc[],
  };
}

function pushBody(partial?: Partial<ReturnType<typeof emptySnapshot>>) {
  return { schemaVersion: 2, snapshot: { ...emptySnapshot(), ...partial } };
}

async function push(body: unknown) {
  return findHandler("syncSnapshotPush")(makeRequest(body), new InvocationContext());
}

async function read() {
  return findHandler("syncSnapshotGet")(makeRequest(), new InvocationContext());
}

// ─── Registration ────────────────────────────────────────────────────────────

describe("registration", () => {
  test("POST handler registers on sync/snapshot", () => {
    const reg = findRegistration("syncSnapshotPush");
    expect(reg.methods).toEqual(["POST"]);
    expect(reg.route).toBe("sync/snapshot");
  });

  test("GET handler registers on sync/snapshot", () => {
    const reg = findRegistration("syncSnapshotGet");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("sync/snapshot");
  });
});

// ─── Auth ────────────────────────────────────────────────────────────────────

describe("authentication", () => {
  test("POST rejects an unauthenticated request without touching Cosmos", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await push(pushBody());
    expect(res.status).toBe(401);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("GET rejects an unauthenticated request without touching Cosmos", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await read();
    expect(res.status).toBe(401);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });
});

// ─── Validation ──────────────────────────────────────────────────────────────

describe("POST validation", () => {
  test("rejects schemaVersion 1 with 400 and explains the expected version", async () => {
    const res = await push({ schemaVersion: 1, snapshot: emptySnapshot() });
    expect(res.status).toBe(400);
    const body = res.jsonBody as { error: string };
    expect(body.error).toContain("2");
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("rejects a missing schemaVersion with 400", async () => {
    const res = await push({ snapshot: emptySnapshot() });
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("rejects a body with no snapshot object with 400", async () => {
    const res = await push({ schemaVersion: 2 });
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("rejects a snapshot missing one of the four arrays with 400", async () => {
    const snapshot = emptySnapshot() as Record<string, unknown>;
    delete snapshot["bodyWeightEntries"];
    const res = await push({ schemaVersion: 2, snapshot });
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("rejects a snapshot where a collection is not an array with 400", async () => {
    const res = await push({
      schemaVersion: 2,
      snapshot: { ...emptySnapshot(), workouts: { id: "w1" } },
    });
    expect(res.status).toBe(400);
  });

  test("rejects a doc without a string id with 400 before writing anything", async () => {
    const workouts = container("workouts");
    const res = await push(
      pushBody({ workouts: [{ id: "w1" }, { name: "no id" }] })
    );
    expect(res.status).toBe(400);
    expect(workouts.upsert).not.toHaveBeenCalled();
  });

  test("rejects a non-JSON body with 400", async () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const badReq = new (HttpRequest as any)(undefined, { "x-api-key": "k" });
    badReq.json = async () => {
      throw new Error("bad json");
    };
    const res = await findHandler("syncSnapshotPush")(badReq, new InvocationContext());
    expect(res.status).toBe(400);
  });
});

// ─── Reconciliation ──────────────────────────────────────────────────────────

describe("POST reconciliation", () => {
  test("upserts every snapshot doc and deletes every absent doc, per container", async () => {
    container("workouts").seed({ id: "w-old" }, { id: "w1", name: "stale" });
    container("templates").seed({ id: "t-old" });
    container("exercises").seed({ id: "e-old" });
    container("bodyWeightEntries").seed({ id: "b-old" });

    const res = await push(
      pushBody({
        workouts: [{ id: "w1", name: "fresh" }, { id: "w2" }],
        templates: [{ id: "t1" }],
        customExercises: [{ id: "e1" }],
        bodyWeightEntries: [{ id: "b1" }, { id: "b2" }],
      })
    );

    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as PushResponseBody;
    expect(body.counts).toEqual({
      workouts: { upserted: 2, deleted: 1 },
      templates: { upserted: 1, deleted: 1 },
      customExercises: { upserted: 1, deleted: 1 },
      bodyWeightEntries: { upserted: 2, deleted: 1 },
    });

    // End state is exactly the snapshot.
    expect(container("workouts").ids()).toEqual(["w1", "w2"]);
    expect(container("workouts").docs.get("w1")).toEqual({ id: "w1", name: "fresh" });
    expect(container("templates").ids()).toEqual(["t1"]);
    expect(container("exercises").ids()).toEqual(["e1"]);
    expect(container("bodyWeightEntries").ids()).toEqual(["b1", "b2"]);
  });

  test("customExercises map to the 'exercises' container, bodyWeightEntries to 'bodyWeightEntries'", async () => {
    await push(
      pushBody({
        customExercises: [{ id: "e1" }],
        bodyWeightEntries: [{ id: "b1" }],
      })
    );
    expect(container("exercises").upsert).toHaveBeenCalledWith(
      expect.objectContaining({ id: "e1" })
    );
    expect(container("bodyWeightEntries").upsert).toHaveBeenCalledWith(
      expect.objectContaining({ id: "b1" })
    );
  });

  test("never touches the chat, insights, or preferences containers", async () => {
    await push(pushBody({ workouts: [{ id: "w1" }] }));
    expect(requestedContainerNames).not.toContain("chat");
    expect(requestedContainerNames).not.toContain("insights");
    expect(requestedContainerNames).not.toContain("preferences");
  });

  test("an empty snapshot wipes all four containers (deletions propagate)", async () => {
    container("workouts").seed({ id: "w1" }, { id: "w2" });
    container("bodyWeightEntries").seed({ id: "b1" });

    const res = await push(pushBody());

    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as PushResponseBody;
    expect(body.counts.workouts).toEqual({ upserted: 0, deleted: 2 });
    expect(body.counts.bodyWeightEntries).toEqual({ upserted: 0, deleted: 1 });
    expect(container("workouts").ids()).toEqual([]);
    expect(container("bodyWeightEntries").ids()).toEqual([]);
  });

  test("reconciliation scan pages through the whole container (no capped scan)", async () => {
    const workouts = container("workouts");
    workouts.pageSize = 2;
    workouts.seed(
      { id: "w1" },
      { id: "w2" },
      { id: "w3" },
      { id: "w4" },
      { id: "w5" },
      { id: "w6" },
      { id: "w7" }
    );

    const res = await push(pushBody({ workouts: [{ id: "w1" }] }));

    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as PushResponseBody;
    // A scan capped at one page would only see 2 of the 7 existing docs.
    expect(body.counts.workouts.deleted).toBe(6);
    expect(workouts.ids()).toEqual(["w1"]);
  });

  test("a delete that 404s (doc concurrently gone) still converges with 200", async () => {
    const workouts = container("workouts");
    workouts.seed({ id: "w1" }, { id: "w-gone" });
    workouts.vanishOnDeleteIds.add("w-gone");

    const res = await push(pushBody({ workouts: [{ id: "w1" }] }));

    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as PushResponseBody;
    expect(body.counts.workouts.deleted).toBe(1);
  });
});

// ─── Revision ────────────────────────────────────────────────────────────────

describe("revision assignment", () => {
  test("first-ever push is revision 1 with an ISO-8601 serverTime", async () => {
    const res = await push(pushBody({ workouts: [{ id: "w1" }] }));
    const body = res.jsonBody as PushResponseBody;
    expect(body.revision).toBe(1);
    expect(Number.isNaN(Date.parse(body.serverTime))).toBe(false);
  });

  test("revision continues from the persisted metadata doc", async () => {
    seedMeta(41);
    const res = await push(pushBody());
    const body = res.jsonBody as PushResponseBody;
    expect(body.revision).toBe(42);
  });

  test("the metadata doc is stamped with the new revision, serverTime and push version", async () => {
    seedMeta(41);
    const res = await push(pushBody());
    const body = res.jsonBody as PushResponseBody;
    const meta = container("syncMeta").docs.get("snapshot");
    // schemaVersion / highestSchemaVersion were added with wire v5: the GET
    // uses the high-water mark to decide whether the v5 keys exist yet.
    expect(meta).toEqual({
      id: "snapshot",
      revision: 42,
      serverTime: body.serverTime,
      schemaVersion: 2,
      highestSchemaVersion: 2,
    });
  });

  test("idempotent re-push: same end state, revision still increments", async () => {
    container("workouts").seed({ id: "w-old" });
    const body = pushBody({ workouts: [{ id: "w1" }], templates: [{ id: "t1" }] });

    const first = await push(body);
    const firstBody = first.jsonBody as PushResponseBody;
    expect(firstBody.revision).toBe(1);
    expect(firstBody.counts.workouts).toEqual({ upserted: 1, deleted: 1 });

    const second = await push(body);
    const secondBody = second.jsonBody as PushResponseBody;
    expect(isOk(second.status)).toBe(true);
    expect(secondBody.revision).toBe(2);
    // Nothing left to delete; upserts are re-applied (revision counts pushes,
    // it does not hash content).
    expect(secondBody.counts.workouts).toEqual({ upserted: 1, deleted: 0 });
    expect(container("workouts").ids()).toEqual(["w1"]);
    expect(container("templates").ids()).toEqual(["t1"]);
  });
});

// ─── Partial failure ─────────────────────────────────────────────────────────

describe("POST partial failure", () => {
  test("a failed delete does not abort the snapshot; 500 with accurate counts", async () => {
    const workouts = container("workouts");
    workouts.seed({ id: "w-keep-fails" }, { id: "w-gone1" }, { id: "w-gone2" });
    workouts.failDeleteIds.add("w-keep-fails");

    const res = await push(pushBody({ workouts: [{ id: "w1" }] }));

    expect(res.status).toBe(500);
    const body = res.jsonBody as {
      error: string;
      failures: string[];
      counts: CountsBody;
    };
    expect(body.error).toBeTruthy();
    expect(body.failures.length).toBe(1);
    // The other two deletes and the upsert still ran.
    expect(body.counts.workouts).toEqual({ upserted: 1, deleted: 2 });
    expect(workouts.ids()).toEqual(["w-keep-fails", "w1"]);
  });

  test("a failed upsert does not abort the snapshot; 500 with accurate counts", async () => {
    const workouts = container("workouts");
    workouts.failUpsertIds.add("w2");

    const res = await push(
      pushBody({ workouts: [{ id: "w1" }, { id: "w2" }, { id: "w3" }] })
    );

    expect(res.status).toBe(500);
    const body = res.jsonBody as { failures: string[]; counts: CountsBody };
    expect(body.failures.length).toBe(1);
    expect(body.counts.workouts.upserted).toBe(2);
    expect(workouts.ids()).toEqual(["w1", "w3"]);
  });

  test("a failed push does not advance the revision; the retry converges and advances it once", async () => {
    seedMeta(7);
    const workouts = container("workouts");
    workouts.seed({ id: "w-stuck" });
    workouts.failDeleteIds.add("w-stuck");

    const failed = await push(pushBody({ workouts: [{ id: "w1" }] }));
    expect(failed.status).toBe(500);
    expect(container("syncMeta").docs.get("snapshot")).toEqual(
      expect.objectContaining({ revision: 7 })
    );

    // The transient failure clears; the client retries the same snapshot.
    workouts.failDeleteIds.clear();
    const retry = await push(pushBody({ workouts: [{ id: "w1" }] }));
    expect(isOk(retry.status)).toBe(true);
    const retryBody = retry.jsonBody as PushResponseBody;
    expect(retryBody.revision).toBe(8);
    expect(workouts.ids()).toEqual(["w1"]);
  });

  test("a failed reconciliation scan is a 500 but upserts are still applied", async () => {
    const workouts = container("workouts");
    workouts.failQuery = true;

    const res = await push(pushBody({ workouts: [{ id: "w1" }] }));

    expect(res.status).toBe(500);
    const body = res.jsonBody as { failures: string[]; counts: CountsBody };
    expect(body.failures.length).toBe(1);
    expect(body.counts.workouts.upserted).toBe(1);
    expect(workouts.docs.has("w1")).toBe(true);
  });
});

// ─── GET (disaster restore) ──────────────────────────────────────────────────

describe("GET /api/sync/snapshot", () => {
  test("returns what POST stored, with the matching revision and serverTime", async () => {
    const pushRes = await push(
      pushBody({
        workouts: [{ id: "w1", name: "Push Day" }],
        templates: [{ id: "t1" }],
        customExercises: [{ id: "e1" }],
        bodyWeightEntries: [{ id: "b1", weightKg: 82.5 }],
      })
    );
    const pushBodyRes = pushRes.jsonBody as PushResponseBody;

    const res = await read();

    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as ReadResponseBody;
    expect(body.revision).toBe(pushBodyRes.revision);
    expect(body.serverTime).toBe(pushBodyRes.serverTime);
    expect(body.snapshot.workouts).toEqual([{ id: "w1", name: "Push Day" }]);
    expect(body.snapshot.templates).toEqual([{ id: "t1" }]);
    expect(body.snapshot.customExercises).toEqual([{ id: "e1" }]);
    expect(body.snapshot.bodyWeightEntries).toEqual([{ id: "b1", weightKg: 82.5 }]);
  });

  test("strips Cosmos system properties from returned docs", async () => {
    container("workouts").seed({
      id: "w1",
      name: "Push Day",
      _rid: "rid",
      _self: "self",
      _etag: '"etag"',
      _attachments: "attachments/",
      _ts: 1234567,
    });

    const res = await read();
    const body = res.jsonBody as ReadResponseBody;
    expect(body.snapshot.workouts).toEqual([{ id: "w1", name: "Push Day" }]);
  });

  test("pages through large containers so the full mirror is returned", async () => {
    const workouts = container("workouts");
    workouts.pageSize = 2;
    workouts.seed({ id: "w1" }, { id: "w2" }, { id: "w3" }, { id: "w4" }, { id: "w5" });

    const res = await read();
    const body = res.jsonBody as ReadResponseBody;
    expect(body.snapshot.workouts.map((w) => w["id"]).sort()).toEqual([
      "w1",
      "w2",
      "w3",
      "w4",
      "w5",
    ]);
  });

  test("an untouched mirror reads as revision 0 with empty arrays", async () => {
    const res = await read();
    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as ReadResponseBody;
    expect(body.revision).toBe(0);
    expect(Number.isNaN(Date.parse(body.serverTime))).toBe(false);
    // A read always returns every mirrored collection, including the ones a
    // v2 push never mentions.
    expect(body.snapshot).toEqual({
      ...emptySnapshot(),
      exerciseReports: [],
      exerciseOverlays: [],
    });
  });

  test("returns 500 when a container read fails", async () => {
    container("templates").failQuery = true;
    const res = await read();
    expect(res.status).toBe(500);
  });
});

// ─── Wire contract v3: exercise reports (issue #135) ─────────────────────────

describe("schemaVersion 3 — exerciseReports", () => {
  function v3Body(reports: Doc[], partial?: Record<string, Doc[]>) {
    return {
      schemaVersion: 3,
      snapshot: { ...emptySnapshot(), ...partial, exerciseReports: reports },
    };
  }

  test("reconciles the exerciseReports container like any other collection", async () => {
    const reports = container("exerciseReports");
    reports.seed({ id: "r-old" });
    seedMeta(4);

    const res = await push(v3Body([{ id: "r-1" }, { id: "r-2" }]));

    expect(res.status ?? 200).toBe(200);
    expect(reports.ids()).toEqual(["r-1", "r-2"]);
    const counts = (res.jsonBody as { counts: Record<string, unknown> }).counts;
    expect(counts["exerciseReports"]).toEqual({ upserted: 2, deleted: 1 });
  });

  test("rejects a v3 push that omits exerciseReports with 400", async () => {
    const res = await push({ schemaVersion: 3, snapshot: emptySnapshot() });
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("an empty array wipes the reports container", async () => {
    const reports = container("exerciseReports");
    reports.seed({ id: "r-1" }, { id: "r-2" });

    const res = await push(v3Body([]));

    expect(res.status ?? 200).toBe(200);
    expect(reports.ids()).toEqual([]);
  });

  test("a v2 push leaves existing reports alone instead of wiping them", async () => {
    // The server deploys independently of the app. A phone still on the old
    // build knows nothing about reports — reading its push as "there are no
    // reports" would silently delete the whole backlog.
    const reports = container("exerciseReports");
    reports.seed({ id: "r-1" }, { id: "r-2" });

    const res = await push(pushBody());

    expect(res.status ?? 200).toBe(200);
    expect(reports.ids()).toEqual(["r-1", "r-2"]);
    expect(requestedContainerNames).not.toContain("exerciseReports");
  });

  test("rejects a v3 push whose exerciseReports is not an array", async () => {
    const res = await push({
      schemaVersion: 3,
      snapshot: { ...emptySnapshot(), exerciseReports: { id: "r-1" } },
    });
    expect(res.status).toBe(400);
  });

  test("rejects an unsupported schemaVersion listing the ones accepted", async () => {
    const res = await push({ schemaVersion: 9, snapshot: emptySnapshot() });
    expect(res.status).toBe(400);
    const body = res.jsonBody as { error: string };
    expect(body.error).toContain("2, 3, 4, 5");
  });

  test("GET returns reports so a restore can rebuild them", async () => {
    seedMeta(7);
    container("exerciseReports").seed({ id: "r-1", detail: "mislabeled" });

    const res = await read();

    const body = res.jsonBody as {
      snapshot: Record<string, Doc[]>;
    };
    expect(body.snapshot["exerciseReports"]).toEqual([
      { id: "r-1", detail: "mislabeled" },
    ]);
  });
});

// ─── schemaVersion 4 — exerciseOverlays (issue #140) ─────────────────────────
// User data added to *bundled* exercises: machine notes and photos. These
// never reached the mirror at all, because only `isCustom` exercises were
// synced — so a note typed at the machine died with the install.
describe("schemaVersion 4 — exerciseOverlays", () => {
  function v4Body(
    overlays: Doc[],
    partial: Record<string, Doc[]> = {}
  ): Record<string, unknown> {
    return {
      schemaVersion: 4,
      snapshot: {
        ...emptySnapshot(),
        ...partial,
        exerciseReports: [],
        exerciseOverlays: overlays,
      },
    };
  }

  test("reconciles the exerciseOverlays container like any other collection", async () => {
    const overlays = container("exerciseOverlays");
    overlays.seed({ id: "Barbell_Squat" });
    seedMeta(11);

    const res = await push(
      v4Body([
        { id: "Barbell_Bench_Press", notes: "seat 4" },
        { id: "Leg_Curl", notes: "pin 7" },
      ])
    );

    expect(res.status ?? 200).toBe(200);
    expect(overlays.ids()).toEqual(["Barbell_Bench_Press", "Leg_Curl"]);
    const counts = (res.jsonBody as { counts: Record<string, unknown> }).counts;
    expect(counts["exerciseOverlays"]).toEqual({ upserted: 2, deleted: 1 });
  });

  test("a v4 push still reconciles every earlier collection", async () => {
    const reports = container("exerciseReports");
    reports.seed({ id: "r-old" });

    const res = await push(v4Body([]));

    expect(res.status ?? 200).toBe(200);
    expect(reports.ids()).toEqual([]);
  });

  test("rejects a v4 push that omits exerciseOverlays with 400", async () => {
    const res = await push({
      schemaVersion: 4,
      snapshot: { ...emptySnapshot(), exerciseReports: [] },
    });
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("an empty array wipes the overlays container", async () => {
    const overlays = container("exerciseOverlays");
    overlays.seed({ id: "Barbell_Squat" }, { id: "Leg_Curl" });

    const res = await push(v4Body([]));

    expect(res.status ?? 200).toBe(200);
    expect(overlays.ids()).toEqual([]);
  });

  test("a v3 push leaves existing overlays alone instead of wiping them", async () => {
    // The same trap #135 set: a phone on the previous build does not know
    // overlays exist, and its silence must not read as "the user deleted
    // every machine note".
    const overlays = container("exerciseOverlays");
    overlays.seed({ id: "Barbell_Squat", notes: "safety bars at 3" });

    const res = await push({
      schemaVersion: 3,
      snapshot: { ...emptySnapshot(), exerciseReports: [] },
    });

    expect(res.status ?? 200).toBe(200);
    expect(overlays.ids()).toEqual(["Barbell_Squat"]);
    expect(requestedContainerNames).not.toContain("exerciseOverlays");
  });

  test("a v2 push leaves overlays alone too", async () => {
    const overlays = container("exerciseOverlays");
    overlays.seed({ id: "Barbell_Squat" });

    const res = await push(pushBody());

    expect(res.status ?? 200).toBe(200);
    expect(overlays.ids()).toEqual(["Barbell_Squat"]);
  });

  test("rejects a v4 push whose exerciseOverlays is not an array", async () => {
    const res = await push({
      schemaVersion: 4,
      snapshot: {
        ...emptySnapshot(),
        exerciseReports: [],
        exerciseOverlays: { id: "Leg_Curl" },
      },
    });
    expect(res.status).toBe(400);
  });

  test("GET returns overlays so a restore can rebuild them", async () => {
    seedMeta(12);
    container("exerciseOverlays").seed({ id: "Leg_Curl", notes: "pin 7" });

    const res = await read();

    const body = res.jsonBody as { snapshot: Record<string, Doc[]> };
    expect(body.snapshot["exerciseOverlays"]).toEqual([
      { id: "Leg_Curl", notes: "pin 7" },
    ]);
  });
});

// ─── schemaVersion 5 — body measurements, medications, alternatives ─────────
// Issues #164 (medication log), #165 (body measurements + height) and #169
// (template alternatives). Four new collections plus a scalar `heightCm`.
//
// The GET rule is the one that protects data: the v5 keys appear ONLY after a
// v5 push has succeeded at least once. Before that, an empty `medications`
// array would tell a restoring phone "the user has no medications" and it
// would wipe its own, never-mirrored records. Absent means unknown.
describe("schemaVersion 5 — v5 collections and heightCm", () => {
  const V5_FIELDS: [string, string][] = [
    ["bodyMeasurements", "bodyMeasurements"],
    ["medications", "medications"],
    ["medicationDoses", "medicationDoses"],
    ["exerciseAlternatives", "exerciseAlternatives"],
  ];

  function v5Snapshot(partial: Record<string, unknown> = {}) {
    return {
      ...emptySnapshot(),
      exerciseReports: [] as Doc[],
      exerciseOverlays: [] as Doc[],
      bodyMeasurements: [] as Doc[],
      medications: [] as Doc[],
      medicationDoses: [] as Doc[],
      exerciseAlternatives: [] as Doc[],
      heightCm: null as unknown,
      ...partial,
    };
  }

  function v5Body(partial: Record<string, unknown> = {}) {
    return { schemaVersion: 5, snapshot: v5Snapshot(partial) };
  }

  function v4Body(partial: Record<string, unknown> = {}) {
    return {
      schemaVersion: 4,
      snapshot: {
        ...emptySnapshot(),
        exerciseReports: [] as Doc[],
        exerciseOverlays: [] as Doc[],
        ...partial,
      },
    };
  }

  const waist = {
    id: "6F1C0000-0000-4000-8000-000000000001",
    site: "waist",
    valueCm: 86.5,
    recordedAt: "2026-11-03T07:00:00.000Z",
    note: "navel, morning",
    lastModified: "2026-11-03T07:00:00.000Z",
  };
  const vial = {
    id: "MED-1",
    name: "Vial A",
    doseForm: "liquid",
    concentrationMgPerMl: 5,
    allowsSyringeUnits: true,
    isArchived: false,
    createdAt: "2026-11-01T00:00:00.000Z",
    lastModified: "2026-11-01T00:00:00.000Z",
  };
  const dose = {
    id: "DOSE-1",
    medicationId: "MED-1",
    takenAt: "2026-11-03T08:00:00.000Z",
    amount: 50,
    unit: "syringeUnits",
    computedMg: 2.5,
    concentrationMgPerMlAtLog: 5,
    lastModified: "2026-11-03T08:00:00.000Z",
  };
  const alternative = {
    id: "ALT-1",
    templateExerciseId: "TE-1",
    externalId: "Leg_Press",
    order: 0,
    note: "if the rack is taken",
    lastModified: "2026-11-03T08:00:00.000Z",
  };

  // ── POST ──

  test.each(V5_FIELDS)(
    "reconciles %s into the %s container like any other collection",
    async (field, containerName) => {
      container(containerName).seed({ id: "old" });

      const res = await push(v5Body({ [field]: [{ id: "a" }, { id: "b" }] }));

      expect(isOk(res.status)).toBe(true);
      expect(container(containerName).ids()).toEqual(["a", "b"]);
      const counts = (res.jsonBody as { counts: Record<string, unknown> }).counts;
      expect(counts[field]).toEqual({ upserted: 2, deleted: 1 });
    }
  );

  test("stores the phone's docs exactly as sent (raw enum strings, as-logged mg)", async () => {
    const res = await push(
      v5Body({
        bodyMeasurements: [waist],
        medications: [vial],
        medicationDoses: [dose],
        exerciseAlternatives: [alternative],
      })
    );

    expect(isOk(res.status)).toBe(true);
    expect(container("bodyMeasurements").docs.get(waist.id)).toEqual(waist);
    expect(container("medications").docs.get(vial.id)).toEqual(vial);
    expect(container("medicationDoses").docs.get(dose.id)).toEqual(dose);
    expect(container("exerciseAlternatives").docs.get(alternative.id)).toEqual(
      alternative
    );
  });

  test("a v5 push still reconciles every earlier collection", async () => {
    container("exerciseOverlays").seed({ id: "Leg_Curl" });
    container("workouts").seed({ id: "w-old" });

    const res = await push(v5Body({ workouts: [{ id: "w1" }] }));

    expect(isOk(res.status)).toBe(true);
    expect(container("exerciseOverlays").ids()).toEqual([]);
    expect(container("workouts").ids()).toEqual(["w1"]);
  });

  test("an empty array wipes that v5 container", async () => {
    container("medicationDoses").seed({ id: "d1" }, { id: "d2" });

    const res = await push(v5Body());

    expect(isOk(res.status)).toBe(true);
    expect(container("medicationDoses").ids()).toEqual([]);
  });

  test.each(V5_FIELDS.map(([field]) => field))(
    "rejects a v5 push that omits %s with 400 before writing anything",
    async (field) => {
      const snapshot = v5Snapshot() as Record<string, unknown>;
      delete snapshot[field];

      const res = await push({ schemaVersion: 5, snapshot });

      expect(res.status).toBe(400);
      expect(mockDatabase.container).not.toHaveBeenCalled();
    }
  );

  test("rejects a v5 doc without a string id with 400", async () => {
    const res = await push(v5Body({ medications: [{ name: "no id" }] }));
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("rejects a v5 push without the heightCm key with 400 (absent is not null)", async () => {
    const snapshot = v5Snapshot() as Record<string, unknown>;
    delete snapshot["heightCm"];

    const res = await push({ schemaVersion: 5, snapshot });

    expect(res.status).toBe(400);
    expect((res.jsonBody as { error: string }).error).toContain("heightCm");
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test.each([[0], [-1], ["182"], [true], [{}], [[]]])(
    "rejects heightCm %j with 400",
    async (heightCm) => {
      const res = await push(v5Body({ heightCm }));
      expect(res.status).toBe(400);
      expect(mockDatabase.container).not.toHaveBeenCalled();
    }
  );

  test("stores heightCm on the sync metadata doc, outside any reconciled container", async () => {
    seedMeta(9);

    const res = await push(v5Body({ heightCm: 182.88 }));

    expect(isOk(res.status)).toBe(true);
    const body = res.jsonBody as PushResponseBody;
    expect(container("syncMeta").docs.get("snapshot")).toEqual({
      id: "snapshot",
      revision: 10,
      serverTime: body.serverTime,
      schemaVersion: 5,
      highestSchemaVersion: 5,
      heightCm: 182.88,
    });
  });

  test("a v5 push with heightCm null records null over an earlier height", async () => {
    container("syncMeta").seed({
      id: "snapshot",
      revision: 1,
      serverTime: "2026-11-01T00:00:00.000Z",
      schemaVersion: 5,
      highestSchemaVersion: 5,
      heightCm: 180,
    });

    await push(v5Body({ heightCm: null }));

    expect(container("syncMeta").docs.get("snapshot")).toEqual(
      expect.objectContaining({ revision: 2, heightCm: null })
    );
  });

  test("a v4 push leaves every v5 container and the height alone", async () => {
    container("bodyMeasurements").seed(waist);
    container("medications").seed(vial);
    container("syncMeta").seed({
      id: "snapshot",
      revision: 3,
      serverTime: "2026-11-01T00:00:00.000Z",
      schemaVersion: 5,
      highestSchemaVersion: 5,
      heightCm: 182.88,
    });

    const res = await push(v4Body());

    expect(isOk(res.status)).toBe(true);
    expect(container("bodyMeasurements").ids()).toEqual([waist.id]);
    expect(container("medications").ids()).toEqual([vial.id]);
    for (const [, name] of V5_FIELDS) {
      expect(requestedContainerNames).not.toContain(name);
    }
    expect(container("syncMeta").docs.get("snapshot")).toEqual(
      expect.objectContaining({
        revision: 4,
        schemaVersion: 4,
        highestSchemaVersion: 5,
        heightCm: 182.88,
      })
    );
  });

  test("a v4 retry that still carries the v5 keys (the phone's fallback) ignores them", async () => {
    // SyncManager steps 5 → 4 on a 400 and resends the SAME snapshot, v5 keys
    // included. Those keys are outside the v4 contract and must not be read.
    container("medications").seed(vial);

    const res = await push({
      schemaVersion: 4,
      snapshot: v5Snapshot({ medications: [], heightCm: 170 }),
    });

    expect(isOk(res.status)).toBe(true);
    expect(container("medications").ids()).toEqual([vial.id]);
    expect(container("syncMeta").docs.get("snapshot")).not.toHaveProperty(
      "heightCm"
    );
  });

  test("a failed v5 push advances nothing: no revision, no height, no v5 high-water mark", async () => {
    seedMeta(7);
    container("medications").failUpsertIds.add(vial.id);

    const res = await push(v5Body({ medications: [vial], heightCm: 182.88 }));

    expect(res.status).toBe(500);
    expect(container("syncMeta").docs.get("snapshot")).toEqual({
      id: "snapshot",
      revision: 7,
      serverTime: "2026-07-01T00:00:00.000Z",
    });
  });

  // ── GET ──

  function snapshotOf(res: { jsonBody?: unknown }): Record<string, unknown> {
    return (res.jsonBody as { snapshot: Record<string, unknown> }).snapshot;
  }

  test("GET on a fresh mirror omits every v5 key — not empty arrays", async () => {
    const res = await read();

    expect(isOk(res.status)).toBe(true);
    const keys = Object.keys(snapshotOf(res));
    for (const [field] of V5_FIELDS) expect(keys).not.toContain(field);
    expect(keys).not.toContain("heightCm");
  });

  test("GET after only v4 pushes omits the v5 keys even if the containers hold docs", async () => {
    // e.g. a v5 push that failed half-way left docs behind: they were never
    // confirmed, so they must not be served as the user's data.
    seedMeta(12);
    container("medications").seed(vial);
    await push(v4Body());

    const res = await read();

    const keys = Object.keys(snapshotOf(res));
    for (const [field] of V5_FIELDS) expect(keys).not.toContain(field);
    expect(keys).not.toContain("heightCm");
    // The v5 containers are not even read.
    for (const [, name] of V5_FIELDS) {
      expect(requestedContainerNames).not.toContain(name);
    }
  });

  test("GET after a v5 push returns all four arrays, even empty, and heightCm", async () => {
    await push(
      v5Body({ bodyMeasurements: [waist], medicationDoses: [dose], heightCm: 182.88 })
    );

    const res = await read();

    const snapshot = snapshotOf(res);
    expect(snapshot["bodyMeasurements"]).toEqual([waist]);
    expect(snapshot["medications"]).toEqual([]);
    expect(snapshot["medicationDoses"]).toEqual([dose]);
    expect(snapshot["exerciseAlternatives"]).toEqual([]);
    expect(snapshot["heightCm"]).toBe(182.88);
  });

  test("GET after a v5 push with no height returns heightCm: null (present, not absent)", async () => {
    await push(v5Body({ heightCm: null }));

    const res = await read();

    expect(snapshotOf(res)).toHaveProperty("heightCm", null);
  });

  test("once a v5 push has succeeded, a later v4 push does not hide the v5 keys again", async () => {
    await push(v5Body({ medications: [vial], heightCm: 175 }));
    await push(v4Body());

    const res = await read();

    const snapshot = snapshotOf(res);
    expect(snapshot["medications"]).toEqual([vial]);
    expect(snapshot["heightCm"]).toBe(175);
  });

  test("GET strips Cosmos system properties from v5 docs too", async () => {
    await push(v5Body());
    container("bodyMeasurements").seed({ ...waist, _rid: "x", _etag: '"e"', _ts: 1 });

    const res = await read();

    expect(snapshotOf(res)["bodyMeasurements"]).toEqual([waist]);
  });
});
