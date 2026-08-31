/**
 * Tests for images/sas Azure Function — issue #91
 *
 * GET /api/images/sas accepted an arbitrary blob `path`, allowing a caller
 * (holding the shared key) to obtain a write/read SAS for any blob in the
 * container instead of just exercises/{exerciseId}.jpg.
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
    process.env.STORAGE_CONNECTION_STRING =
      "DefaultEndpointsProtocol=https;AccountName=teststorage;AccountKey=dGVzdGtleQ==;EndpointSuffix=core.windows.net";
    const result = await handler(
      makeRequest({ path: `exercises/${VALID_ID}.jpg`, mode: "download" }),
      new InvocationContext()
    );
    // A valid path clears validation and reaches SAS generation (200), not 400.
    expect(result.status).not.toBe(400);
  });
});
