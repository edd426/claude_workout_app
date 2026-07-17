/**
 * Tests for syncPush Azure Function — issue #74
 *
 * #74: syncPush aggregated every per-record outcome into { accepted, conflicts }
 *      and returned HTTP 200 even when individual Cosmos upserts threw — those
 *      failures were silently folded into `conflicts`. The iOS client, unable to
 *      tell which records were actually written, marked everything synced →
 *      silent data loss.
 *
 *      Fix: return a per-record `results` array distinguishing
 *      "accepted" / "conflict" / "error", while keeping the aggregate
 *      accepted/conflicts/serverTimestamp fields for backward compatibility.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { mockItems, mockItemRead, mockContainer, mockDatabase } from "./__mocks__/cosmos";
import "../src/functions/syncPush";

// `app` is the mock stub from moduleNameMapper; syncPush.ts imported the same
// stub (same module registry instance via static import), so app.http.mock.calls
// is already populated by the time beforeAll runs.
const mockApp = app as unknown as { http: jest.Mock };

interface PushResult {
  id: string;
  collection: string;
  status: "accepted" | "conflict" | "error";
}

interface PushResponse {
  accepted: number;
  conflicts: number;
  serverTimestamp: string;
  results: PushResult[];
}

type Handler = (
  req: unknown,
  ctx: InvocationContext
) => Promise<{ status?: number; jsonBody?: PushResponse }>;

let handler: Handler;

beforeAll(() => {
  const call = mockApp.http.mock.calls.find(([name]: [string]) => name === "syncPush");
  if (!call) throw new Error("syncPush handler was not registered with app.http()");
  handler = call[1].handler;
});

beforeEach(() => {
  // Fresh mock behaviour per test: no existing server docs, upserts succeed.
  mockDatabase.container.mockClear();
  mockItems.upsert.mockReset();
  mockItems.upsert.mockResolvedValue({});
  mockItemRead.mockReset();
  mockItemRead.mockResolvedValue({ resource: undefined });
  mockContainer.item.mockReset();
  mockContainer.item.mockReturnValue({ read: mockItemRead });
});

function makeRequest(body: unknown, apiKey = "test-key") {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(body, { "x-api-key": apiKey });
}

function makeContext() {
  return new InvocationContext();
}

function isOk(status?: number) {
  // Azure Functions treats an undefined status as 200.
  return status === undefined || status === 200;
}

// ─── Issue #74 RED tests ─────────────────────────────────────────────────────

describe("syncPush — issue #74: per-record results in push response", () => {
  test("(a) all-new records are accepted, each with its own result entry", async () => {
    const req = makeRequest({
      workouts: [
        { id: "w1", lastModified: "2026-07-01T00:00:00.000Z" },
        { id: "w2", lastModified: "2026-07-02T00:00:00.000Z" },
      ],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(isOk(res.status)).toBe(true);
    expect(body.accepted).toBe(2);
    expect(body.conflicts).toBe(0);
    expect(body.results).toHaveLength(2);
    expect(body.results).toEqual(
      expect.arrayContaining([
        { id: "w1", collection: "workouts", status: "accepted" },
        { id: "w2", collection: "workouts", status: "accepted" },
      ])
    );
    expect(mockItems.upsert).toHaveBeenCalledTimes(2);
  });

  test("(b) a stale record (older than the server copy) is a conflict and is not written", async () => {
    // Server already holds a newer w1; w2 does not exist yet.
    mockContainer.item.mockImplementation((id: string) => ({
      read: async () => ({
        resource:
          id === "w1"
            ? { id: "w1", lastModified: "2026-06-01T00:00:00.000Z" }
            : undefined,
      }),
    }));

    const req = makeRequest({
      workouts: [
        { id: "w1", lastModified: "2026-01-01T00:00:00.000Z" }, // older → loses LWW
        { id: "w2", lastModified: "2026-07-02T00:00:00.000Z" }, // new → accepted
      ],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(isOk(res.status)).toBe(true);
    expect(body.accepted).toBe(1);
    expect(body.conflicts).toBe(1);
    expect(body.results).toEqual(
      expect.arrayContaining([
        { id: "w1", collection: "workouts", status: "conflict" },
        { id: "w2", collection: "workouts", status: "accepted" },
      ])
    );
    // The losing record must NOT be written — server copy stays untouched.
    expect(mockItems.upsert).toHaveBeenCalledTimes(1);
    expect(mockItems.upsert).toHaveBeenCalledWith(expect.objectContaining({ id: "w2" }));
  });

  test("(c) a Cosmos upsert failure yields status 'error' for that record only, others still accepted, HTTP 200", async () => {
    mockItems.upsert.mockImplementation(async (record: { id: string }) => {
      if (record.id === "w2") throw new Error("Cosmos write failed");
      return {};
    });

    const req = makeRequest({
      workouts: [
        { id: "w1", lastModified: "2026-07-01T00:00:00.000Z" },
        { id: "w2", lastModified: "2026-07-02T00:00:00.000Z" },
        { id: "w3", lastModified: "2026-07-03T00:00:00.000Z" },
      ],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(isOk(res.status)).toBe(true);
    expect(body.accepted).toBe(2);
    // The failure must NOT be folded into conflicts.
    expect(body.conflicts).toBe(0);
    expect(body.results).toEqual(
      expect.arrayContaining([
        { id: "w1", collection: "workouts", status: "accepted" },
        { id: "w2", collection: "workouts", status: "error" },
        { id: "w3", collection: "workouts", status: "accepted" },
      ])
    );
  });

  test("(d) results contains an entry for every submitted record with the correct collection name", async () => {
    const req = makeRequest({
      workouts: [{ id: "w1", lastModified: "2026-07-01T00:00:00.000Z" }],
      templates: [
        { id: "t1", lastModified: "2026-07-01T00:00:00.000Z" },
        { id: "t2", lastModified: "2026-07-02T00:00:00.000Z" },
      ],
      insights: [{ id: "i1", lastModified: "2026-07-01T00:00:00.000Z" }],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(body.results).toHaveLength(4);
    const collectionById = Object.fromEntries(
      body.results.map((r) => [r.id, r.collection])
    );
    expect(collectionById["w1"]).toBe("workouts");
    expect(collectionById["t1"]).toBe("templates");
    expect(collectionById["t2"]).toBe("templates");
    expect(collectionById["i1"]).toBe("insights");
  });

  test("a non-404 read failure yields 'error' and does NOT upsert (no LWW bypass)", async () => {
    // A throttling/outage error during the existence check must not be treated
    // as "document doesn't exist" — that would overwrite a possibly-newer
    // server copy without the LWW comparison ever running.
    mockItemRead.mockRejectedValue({ code: 503 });

    const req = makeRequest({
      workouts: [{ id: "w1", lastModified: "2026-07-01T00:00:00.000Z" }],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(isOk(res.status)).toBe(true);
    expect(body.results).toEqual([
      { id: "w1", collection: "workouts", status: "error" },
    ]);
    expect(mockItems.upsert).not.toHaveBeenCalled();
  });

  test("a confirmed 404 read still means 'new record' and upserts", async () => {
    mockItemRead.mockRejectedValue({ code: 404 });

    const req = makeRequest({
      workouts: [{ id: "w1", lastModified: "2026-07-01T00:00:00.000Z" }],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(body.results).toEqual([
      { id: "w1", collection: "workouts", status: "accepted" },
    ]);
    expect(mockItems.upsert).toHaveBeenCalledTimes(1);
  });

  test("a record missing an id is reported as an 'error', not silently dropped", async () => {
    const req = makeRequest({
      workouts: [
        { lastModified: "2026-07-01T00:00:00.000Z" }, // no id → validation failure
        { id: "w2", lastModified: "2026-07-02T00:00:00.000Z" },
      ],
    });

    const res = await handler(req, makeContext());
    const body = res.jsonBody!;

    expect(isOk(res.status)).toBe(true);
    expect(body.accepted).toBe(1);
    expect(body.conflicts).toBe(0);
    expect(body.results).toHaveLength(2);
    expect(body.results.filter((r) => r.status === "error")).toHaveLength(1);
  });
});
