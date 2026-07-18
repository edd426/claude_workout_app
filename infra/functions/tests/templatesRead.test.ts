/**
 * Tests for template read endpoints — issue #79
 *
 * GET /api/templates       — list all templates (bounded)
 * GET /api/templates/{id}  — get one template by id
 *
 * These endpoints back the read-only MCP tools (list_templates, get_template)
 * after the MCP server is re-routed through the Functions API.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import {
  mockItems,
  mockItemRead,
  mockFetchAll,
  resetCosmosDb,
} from "./__mocks__/cosmos";
import "../src/functions/templates";

const mockApp = app as unknown as { http: jest.Mock };
const mockAuthenticate = authenticate as jest.Mock;

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

function makeRequest(options?: {
  query?: Record<string, string>;
  params?: Record<string, string>;
}) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(undefined, { "x-api-key": "test-key" }, options);
}

const sampleTemplate = {
  id: "tmpl-1",
  name: "Push Day",
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:00Z",
  timesPerformed: 5,
  exercises: [
    {
      id: "te-1",
      order: 0,
      exerciseId: "ex-1",
      exerciseName: "Bench Press",
      defaultSets: 3,
      defaultReps: 10,
      defaultRestSeconds: 90,
    },
  ],
};

beforeEach(() => {
  // Do NOT use jest.clearAllMocks() — it would wipe the app.http registration
  // calls captured at import time. Clear only the per-test mocks.
  mockItems.query.mockClear();
  mockFetchAll.mockClear();
  mockItemRead.mockClear();
  resetCosmosDb();
  mockAuthenticate.mockReturnValue(null);
});

describe("GET /api/templates — list", () => {
  test("registers with GET method and templates route", () => {
    const reg = findRegistration("templatesList");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("templates");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("templatesList")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(401);
    expect(mockItems.query).not.toHaveBeenCalled();
  });

  test("returns templates from Cosmos", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleTemplate] });

    const res = await findHandler("templatesList")(makeRequest(), new InvocationContext());

    expect(res.status ?? 200).toBe(200);
    expect(res.jsonBody).toEqual({ templates: [sampleTemplate] });
  });

  test("bounds the query with a LIMIT parameter", async () => {
    await findHandler("templatesList")(makeRequest(), new InvocationContext());

    const [queryArg] = mockItems.query.mock.calls[0];
    expect(queryArg.query).toContain("LIMIT");
    const limitParam = queryArg.parameters.find(
      (p: { name: string }) => p.name === "@limit"
    );
    expect(limitParam).toBeDefined();
    expect(limitParam.value).toBeLessThanOrEqual(200);
  });

  test("rejects a non-numeric limit with 400", async () => {
    const res = await findHandler("templatesList")(
      makeRequest({ query: { limit: "banana" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(400);
  });

  test("caps an oversized limit instead of passing it through", async () => {
    await findHandler("templatesList")(
      makeRequest({ query: { limit: "99999" } }),
      new InvocationContext()
    );
    const [queryArg] = mockItems.query.mock.calls[0];
    const limitParam = queryArg.parameters.find(
      (p: { name: string }) => p.name === "@limit"
    );
    expect(limitParam.value).toBeLessThanOrEqual(200);
  });

  test("returns 500 when Cosmos fails", async () => {
    mockFetchAll.mockRejectedValue(new Error("boom"));
    const res = await findHandler("templatesList")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(500);
  });
});

describe("GET /api/templates/{id} — detail", () => {
  test("registers with GET method and templates/{id} route", () => {
    const reg = findRegistration("templatesGet");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("templates/{id}");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("templatesGet")(
      makeRequest({ params: { id: "tmpl-1" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(401);
  });

  test("returns the template when found", async () => {
    mockItemRead.mockResolvedValue({ resource: sampleTemplate });

    const res = await findHandler("templatesGet")(
      makeRequest({ params: { id: "tmpl-1" } }),
      new InvocationContext()
    );

    expect(res.status ?? 200).toBe(200);
    expect(res.jsonBody).toEqual(sampleTemplate);
  });

  test("returns 404 when the read resolves with no resource", async () => {
    mockItemRead.mockResolvedValue({ resource: undefined });

    const res = await findHandler("templatesGet")(
      makeRequest({ params: { id: "missing" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(404);
  });

  test("returns 404 when the read throws a 404 error", async () => {
    mockItemRead.mockRejectedValue({ code: 404 });

    const res = await findHandler("templatesGet")(
      makeRequest({ params: { id: "missing" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(404);
  });

  test("returns 400 when id route param is missing", async () => {
    const res = await findHandler("templatesGet")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(400);
  });
});
