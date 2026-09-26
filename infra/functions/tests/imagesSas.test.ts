/**
 * Tests for images/sas Azure Function — issue #91
 *
 * GET /api/images/sas accepted an arbitrary blob `path`, allowing a caller
 * (holding the shared key) to obtain a write/read SAS for any blob in the
 * container instead of just exercises/{exerciseId}.jpg.
 *
 * Issue #141 adds exactly one more family, reports/{reportId}.jpg, for photos
 * attached to exercise reports. Everything else stays locked.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import "../src/functions/imagesSas";

const mockApp = app as unknown as { http: jest.Mock };

type Handler = (
  req: unknown,
  ctx: InvocationContext
) => Promise<{ status?: number; jsonBody?: unknown }>;

let handler: Handler;

beforeAll(() => {
  const call = mockApp.http.mock.calls.find(([name]: [string]) => name === "imagesSas");
  if (!call) throw new Error("imagesSas handler was not registered with app.http()");
  handler = call[1].handler;
});

function makeRequest(query: Record<string, string>) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(undefined, { "x-api-key": "test-key" }, { query });
}

const VALID_ID = "6e4b1c2a-9d3f-4e21-8a7b-0c1d2e3f4a5b";
// Swift's `uuidString` is upper-case, which is what the phone actually sends.
const UPPER_ID = "6E4B1C2A-9D3F-4E21-8A7B-0C1D2E3F4A5B";

const TEST_CONNECTION_STRING =
  "DefaultEndpointsProtocol=https;AccountName=teststorage;AccountKey=dGVzdGtleQ==;EndpointSuffix=core.windows.net";

describe("imagesSas — issue #91: path validation", () => {
  test("rejects path traversal with 400", async () => {
    const result = await handler(
      makeRequest({ path: `exercises/../../../etc/passwd`, mode: "download" }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("rejects an arbitrary blob path outside the exercises/ convention", async () => {
    const result = await handler(
      makeRequest({ path: "some-other-container-secret.jpg", mode: "download" }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("rejects a path with a nested segment", async () => {
    const result = await handler(
      makeRequest({ path: `exercises/nested/${VALID_ID}.jpg`, mode: "upload" }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("rejects a non-.jpg extension", async () => {
    const result = await handler(
      makeRequest({ path: `exercises/${VALID_ID}.png`, mode: "download" }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("rejects a missing path", async () => {
    const result = await handler(
      makeRequest({ mode: "download" }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("rejects an invalid mode even with a valid path", async () => {
    const result = await handler(
      makeRequest({ path: `exercises/${VALID_ID}.jpg`, mode: "delete" }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("accepts the documented exercises/{exerciseId}.jpg convention (path validation passes)", async () => {
    process.env.STORAGE_CONNECTION_STRING = TEST_CONNECTION_STRING;
    const result = await handler(
      makeRequest({ path: `exercises/${VALID_ID}.jpg`, mode: "download" }),
      new InvocationContext()
    );
    // A valid path clears validation and reaches SAS generation (200), not 400.
    expect(result.status).not.toBe(400);
  });
});

// ─── Issue #141: photos attached to exercise reports ──────────────────────────
// The phone uploads a report's photo to reports/{reportId}.jpg, where reportId
// is the ExerciseReport UUID (Swift `uuidString` — upper-case hex). This is a
// second path family added deliberately; the #91 lock on everything else stays.

describe("imagesSas — issue #141: reports/{reportId}.jpg path family", () => {
  beforeEach(() => {
    process.env.STORAGE_CONNECTION_STRING = TEST_CONNECTION_STRING;
  });

  test.each([
    ["reports", VALID_ID, "upload"],
    ["reports", VALID_ID, "download"],
    ["reports", UPPER_ID, "upload"],
    ["reports", UPPER_ID, "download"],
    // The exercises family must survive the change unchanged.
    ["exercises", VALID_ID, "upload"],
    ["exercises", UPPER_ID, "download"],
  ])(
    "issues an HTTPS-only SAS for %s/{id}.jpg (id %s, mode %s)",
    async (family, id, mode) => {
      const path = `${family}/${id}.jpg`;

      const result = await handler(
        makeRequest({ path, mode }),
        new InvocationContext()
      );

      expect(result.status ?? 200).toBe(200);
      const body = result.jsonBody as { sasUrl: string; expiresAt: string };
      const url = new URL(body.sasUrl);
      expect(url.pathname).toBe(`/workout-images/${path}`);
      expect(url.searchParams.get("spr")).toBe("https");
      // Upload grants create+write only; download grants read only.
      expect(url.searchParams.get("sp")).toBe(mode === "upload" ? "cw" : "r");
      expect(Number.isNaN(Date.parse(body.expiresAt))).toBe(false);
    }
  );

  const rejected = [
    `reports/../exercises/x.jpg`,
    `reports/../exercises/${VALID_ID}.jpg`,
    `reports/not-a-uuid.jpg`,
    `reports/${VALID_ID}.png`,
    `reports/${VALID_ID}.jpg/extra`,
    `reports/nested/${VALID_ID}.jpg`,
    `/reports/${VALID_ID}.jpg`,
    `report/${VALID_ID}.jpg`,
    `foo/${VALID_ID}.jpg`,
    `reports/${VALID_ID}.jpg\n`,
  ];

  test.each(
    rejected.flatMap((path) => [
      [path, "upload"],
      [path, "download"],
    ])
  )("rejects %j (mode %s) with 400", async (path, mode) => {
    const result = await handler(
      makeRequest({ path, mode }),
      new InvocationContext()
    );
    expect(result.status).toBe(400);
  });

  test("the 400 names both accepted path families", async () => {
    const result = await handler(
      makeRequest({ path: `foo/${VALID_ID}.jpg`, mode: "upload" }),
      new InvocationContext()
    );
    const { error } = result.jsonBody as { error: string };
    expect(error).toContain("exercises/{exerciseId}.jpg");
    expect(error).toContain("reports/{reportId}.jpg");
  });
});
