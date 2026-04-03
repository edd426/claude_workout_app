/**
 * Tests for syncPull Azure Function — issue #35
 *
 * #35: First-ever sync (null/missing lastSyncTimestamp) was rejected with 400.
 *      Fix: only require `collections`; default timestamp to epoch.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { mockItems } from "./__mocks__/cosmos";
import "../src/functions/syncPull";

// `app` is the mock stub from moduleNameMapper; syncPull.ts also imported the same
// stub (same module registry instance via static import), so app.http.mock.calls
// is already populated by the time beforeAll runs.
const mockApp = app as unknown as { http: jest.Mock };

type Handler = (req: unknown, ctx: InvocationContext) => Promise<{ status?: number; jsonBody?: unknown }>;

let handler: Handler;

beforeAll(() => {
  const call = mockApp.http.mock.calls.find(([name]: [string]) => name === "syncPull");
  if (!call) throw new Error("syncPull handler was not registered with app.http()");
  handler = call[1].handler;
});

function makeRequest(body: unknown, apiKey = "test-key") {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(body, { "x-api-key": apiKey });
}

function makeContext() {
  return new InvocationContext();
}

// ─── Issue #35 RED tests ────────────────────────────────────────────────────

describe("syncPull — issue #35: first-ever sync with null timestamp", () => {
  beforeEach(() => {
    mockItems.query.mockClear();
  });

  test("returns 200 when lastSyncTimestamp is null (first sync)", async () => {
    const req = makeRequest({ lastSyncTimestamp: null, collections: ["workouts"] });
    const res = await handler(req, makeContext());
    // Before fix: returns 400 ("Missing required fields: lastSyncTimestamp, collections")
    // After fix: returns 200 (status undefined in Azure Functions = 200)
    expect(res.status).not.toBe(400);
    expect(res.status === undefined || res.status === 200).toBe(true);
  });

  test("returns 200 when lastSyncTimestamp is absent entirely (first sync)", async () => {
    const req = makeRequest({ collections: ["workouts"] });
    const res = await handler(req, makeContext());
    expect(res.status).not.toBe(400);
    expect(res.status === undefined || res.status === 200).toBe(true);
  });

  test("returns 400 when collections is missing (still required)", async () => {
    const req = makeRequest({ lastSyncTimestamp: null });
    const res = await handler(req, makeContext());
    expect(res.status).toBe(400);
  });

  test("queries Cosmos DB with epoch timestamp when lastSyncTimestamp is null", async () => {
    const req = makeRequest({ lastSyncTimestamp: null, collections: ["workouts"] });
    await handler(req, makeContext());

    expect(mockItems.query).toHaveBeenCalledWith(
      expect.objectContaining({
        parameters: expect.arrayContaining([
          expect.objectContaining({ name: "@lastSync", value: "1970-01-01T00:00:00.000Z" }),
        ]),
      })
    );
  });

  test("queries Cosmos DB with epoch timestamp when lastSyncTimestamp is absent", async () => {
    const req = makeRequest({ collections: ["templates"] });
    await handler(req, makeContext());

    expect(mockItems.query).toHaveBeenCalledWith(
      expect.objectContaining({
        parameters: expect.arrayContaining([
          expect.objectContaining({ name: "@lastSync", value: "1970-01-01T00:00:00.000Z" }),
        ]),
      })
    );
  });
});
