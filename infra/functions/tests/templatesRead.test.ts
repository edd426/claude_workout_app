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
  mockDatabase,
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

  test("never serves the snapshot's content hash or Cosmos system fields", async () => {
    mockItemRead.mockResolvedValue({
      resource: { ...sampleTemplate, mirrorContentHash: "a".repeat(64), _rid: "r", _ts: 1, _etag: "e" },
    });

    const res = await findHandler("templatesGet")(
      makeRequest({ params: { id: "tmpl-1" } }),
      new InvocationContext()
    );

    expect(res.jsonBody).toStrictEqual(sampleTemplate);
  });

  test("the list never serves them either", async () => {
    mockFetchAll.mockResolvedValue({
      resources: [{ ...sampleTemplate, mirrorContentHash: "a".repeat(64), _rid: "r" }],
    });

    const res = await findHandler("templatesList")(makeRequest(), new InvocationContext());

    expect((res.jsonBody as { templates: unknown[] }).templates).toStrictEqual([sampleTemplate]);
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

// ─── #169: alternatives joined onto each template exercise ───────────────────
// The mirror stores alternatives in their own container, keyed by
// `templateExerciseId`. get_template joins them, in `order`, once a v5 push
// has landed; before that the key is omitted (unknown), never [] (none).
describe("GET /api/templates/{id} — alternatives (#169)", () => {
  type Doc = Record<string, unknown>;

  const legs = {
    id: "TMPL-LEGS",
    name: "Legs",
    createdAt: "2026-11-01T00:00:00Z",
    updatedAt: "2026-11-01T00:00:00Z",
    timesPerformed: 0,
    exercises: [
      {
        id: "TE-SQUAT",
        order: 0,
        exerciseId: "ex-1",
        exerciseName: "Barbell Squat",
        defaultSets: 3,
        defaultReps: 5,
        defaultRestSeconds: 180,
      },
      {
        id: "TE-CURL",
        order: 1,
        exerciseId: "ex-2",
        exerciseName: "Leg Curl",
        defaultSets: 3,
        defaultReps: 12,
        defaultRestSeconds: 90,
      },
    ],
  };

  const smith = {
    id: "ALT-2",
    templateExerciseId: "TE-SQUAT",
    externalId: "Smith_Machine_Squat",
    order: 1,
    lastModified: "2026-11-03T08:00:00Z",
    _rid: "x",
    _ts: 1,
  };
  const legPress = {
    id: "ALT-1",
    templateExerciseId: "TE-SQUAT",
    externalId: "Leg_Press",
    order: 0,
    note: "if the rack is taken",
    lastModified: "2026-11-03T08:00:00Z",
  };

  let meta: Doc | undefined;
  let alternatives: Doc[];
  let alternativesQuery: jest.Mock;

  beforeEach(() => {
    meta = {
      id: "snapshot",
      revision: 4,
      serverTime: "2026-11-03T09:00:00Z",
      schemaVersion: 5,
      highestSchemaVersion: 5,
    };
    alternatives = [smith, legPress];
    alternativesQuery = jest.fn(() => ({
      fetchAll: async () => ({ resources: alternatives }),
    }));
    mockDatabase.container.mockImplementation((name: string) => {
      if (name === "templates") {
        return { item: () => ({ read: async () => ({ resource: legs }) }) };
      }
      if (name === "syncMeta") {
        return { item: () => ({ read: async () => ({ resource: meta }) }) };
      }
      if (name === "exerciseAlternatives") {
        return { items: { query: alternativesQuery } };
      }
      throw new Error(`unexpected container ${name}`);
    });
  });

  async function getLegs() {
    return findHandler("templatesGet")(
      makeRequest({ params: { id: "TMPL-LEGS" } }),
      new InvocationContext()
    );
  }

  test("each exercise carries its alternatives in order, without Cosmos system props", async () => {
    const res = await getLegs();

    expect(res.status ?? 200).toBe(200);
    const body = res.jsonBody as { exercises: Doc[] };
    expect(body.exercises[0]["alternatives"]).toEqual([
      { externalId: "Leg_Press", note: "if the rack is taken", order: 0 },
      { externalId: "Smith_Machine_Squat", order: 1 },
    ]);
  });

  test("an exercise with no alternatives gets [] once v5 is mirrored", async () => {
    const res = await getLegs();
    const body = res.jsonBody as { exercises: Doc[] };
    expect(body.exercises[1]["alternatives"]).toEqual([]);
  });

  test("queries only this template's exercise ids", async () => {
    await getLegs();
    const [[spec]] = alternativesQuery.mock.calls as unknown as [[{
      query: string;
      parameters: { name: string; value: unknown }[];
    }]];
    expect(spec.query).toContain("ARRAY_CONTAINS(@ids, c.templateExerciseId)");
    expect(spec.parameters).toEqual([{ name: "@ids", value: ["TE-SQUAT", "TE-CURL"] }]);
  });

  test("before any v5 push the alternatives key is omitted and the container is not read", async () => {
    meta = { id: "snapshot", revision: 2, serverTime: "x", highestSchemaVersion: 4 };

    const res = await getLegs();

    const body = res.jsonBody as { exercises: Doc[] };
    expect(body.exercises[0]).not.toHaveProperty("alternatives");
    expect(alternativesQuery).not.toHaveBeenCalled();
  });

  test("a failed alternatives read still returns the template, without the key", async () => {
    alternativesQuery.mockImplementation(() => ({
      fetchAll: async () => {
        throw new Error("boom");
      },
    }));

    const res = await getLegs();

    expect(res.status ?? 200).toBe(200);
    const body = res.jsonBody as { name: string; exercises: Doc[] };
    expect(body.name).toBe("Legs");
    expect(body.exercises[0]).not.toHaveProperty("alternatives");
  });
});
