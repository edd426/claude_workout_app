/**
 * Tests for the v5 health read endpoints — issues #164 and #165.
 *
 * GET /api/body-measurements — circumference log + height (+ latest waist)
 * GET /api/medications       — user-defined medications
 * GET /api/medication-doses  — the dose log, joined to medication names
 *
 * These back the MCP tools list_body_measurements, list_medications and
 * list_medication_logs. Like the snapshot GET, they report `mirrored: false`
 * and read nothing until a v5 push has succeeded: before that the containers
 * hold nothing the phone confirmed, and "none" would be a false answer.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import { mockDatabase, resetCosmosDb } from "./__mocks__/cosmos";
import "../src/functions/bodyMeasurements";
import "../src/functions/medications";

const mockApp = app as unknown as { http: jest.Mock };
const mockAuthenticate = authenticate as jest.Mock;

type Doc = Record<string, unknown>;

type Handler = (
  req: unknown,
  ctx: InvocationContext
) => Promise<{ status?: number; jsonBody?: unknown }>;

function findRegistration(name: string): Record<string, unknown> {
  const call = mockApp.http.mock.calls.find(([n]: [string]) => n === name);
  if (!call) throw new Error(`${name} was not registered with app.http()`);
  return call[1];
}

function handler(name: string): Handler {
  return findRegistration(name)["handler"] as Handler;
}

function makeRequest(query: Record<string, string> = {}) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(undefined, { "x-api-key": "k" }, { query });
}

// ─── Per-container fakes ─────────────────────────────────────────────────────
// SQL is not evaluated: each container returns its seeded docs for every
// query, and tests assert the query text and parameters that do the filtering.

interface FakeContainer {
  docs: Doc[];
  queries: { query: string; parameters?: { name: string; value: unknown }[] }[];
  items: { query: jest.Mock };
  item: jest.Mock;
  /** Results for the Nth query, overriding `docs`. */
  queryResults: Doc[][];
}

let containers: Record<string, FakeContainer>;
let requested: string[];
let context: InvocationContext;

function container(name: string): FakeContainer {
  if (!containers[name]) {
    const fake: FakeContainer = {
      docs: [],
      queries: [],
      queryResults: [],
      items: { query: jest.fn() },
      item: jest.fn(),
    };
    fake.items.query.mockImplementation((spec) => {
      fake.queries.push(spec);
      const resources = fake.queryResults.shift() ?? fake.docs;
      return { fetchAll: async () => ({ resources }) };
    });
    fake.item.mockImplementation((id: string) => ({
      read: async () => ({ resource: fake.docs.find((doc) => doc["id"] === id) }),
    }));
    containers[name] = fake;
  }
  return containers[name];
}

function mirrorV5(heightCm: number | null = 182.88) {
  container("syncMeta").docs.push({
    id: "snapshot",
    revision: 3,
    serverTime: "2026-11-03T09:00:00.000Z",
    schemaVersion: 5,
    highestSchemaVersion: 5,
    heightCm,
  });
}

function mirrorV4Only() {
  container("syncMeta").docs.push({
    id: "snapshot",
    revision: 2,
    serverTime: "2026-11-02T09:00:00.000Z",
    schemaVersion: 4,
    highestSchemaVersion: 4,
  });
}

beforeEach(() => {
  resetCosmosDb();
  containers = {};
  requested = [];
  context = new InvocationContext();
  mockDatabase.container.mockReset();
  mockDatabase.container.mockImplementation((name: string) => {
    requested.push(name);
    return container(name);
  });
  mockAuthenticate.mockReturnValue(null);
});

const waist = {
  id: "M-1",
  site: "waist",
  valueCm: 86.5,
  recordedAt: "2026-11-03T07:00:00.000Z",
  note: "navel, morning",
  lastModified: "2026-11-03T07:00:00.000Z",
};

const vial = {
  id: "AAAAAAAA-0000-4000-8000-000000000001",
  name: "Vial A",
  doseForm: "liquid",
  concentrationMgPerMl: 5,
  allowsSyringeUnits: true,
  isArchived: false,
  createdAt: "2026-11-01T00:00:00.000Z",
  lastModified: "2026-11-01T00:00:00.000Z",
};

const tablets = {
  id: "BBBBBBBB-0000-4000-8000-000000000002",
  name: "anti-inflammatory",
  doseForm: "tablet",
  tabletStrengthMg: 50,
  allowsSyringeUnits: false,
  isArchived: true,
  createdAt: "2026-10-01T00:00:00.000Z",
  lastModified: "2026-10-01T00:00:00.000Z",
};

const dose = {
  id: "D-1",
  medicationId: vial.id,
  takenAt: "2026-11-03T08:00:00.000Z",
  amount: 50,
  unit: "syringeUnits",
  computedMg: 2.5,
  concentrationMgPerMlAtLog: 5,
  lastModified: "2026-11-03T08:00:00.000Z",
};

// ─── Registration and auth ───────────────────────────────────────────────────

describe("registration and auth", () => {
  test.each([
    ["bodyMeasurementsList", "body-measurements"],
    ["medicationsList", "medications"],
    ["medicationDosesList", "medication-doses"],
  ])("%s registers GET on %s", (name, route) => {
    const reg = findRegistration(name);
    expect(reg["methods"]).toEqual(["GET"]);
    expect(reg["route"]).toBe(route);
  });

  test.each(["bodyMeasurementsList", "medicationsList", "medicationDosesList"])(
    "%s requires the API key and touches nothing without it",
    async (name) => {
      mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
      const res = await handler(name)(makeRequest(), context);
      expect(res.status).toBe(401);
      expect(mockDatabase.container).not.toHaveBeenCalled();
    }
  );
});

// ─── Not mirrored yet ────────────────────────────────────────────────────────

describe("before any v5 push", () => {
  test.each([
    ["bodyMeasurementsList", { mirrored: false, heightCm: null, measurements: [], latestWaist: null }],
    ["medicationsList", { mirrored: false, medications: [] }],
    ["medicationDosesList", { mirrored: false, doses: [] }],
  ])(
    "%s answers mirrored: false and never reads the v5 containers",
    async (name, expected) => {
      mirrorV4Only();
      const res = await handler(name)(makeRequest(), context);
      expect(res.status ?? 200).toBe(200);
      expect(res.jsonBody).toEqual(expected);
      expect(requested).toEqual(["syncMeta"]);
    }
  );

  test("a fresh mirror with no metadata doc is not mirrored either", async () => {
    const res = await handler("medicationsList")(makeRequest(), context);
    expect(res.jsonBody).toEqual({ mirrored: false, medications: [] });
  });
});

// ─── GET /api/body-measurements ──────────────────────────────────────────────

describe("GET /api/body-measurements", () => {
  test("returns the measurements, the height and the latest waist", async () => {
    mirrorV5(182.88);
    const measurements = container("bodyMeasurements");
    measurements.queryResults.push([waist], [waist]);

    const res = await handler("bodyMeasurementsList")(makeRequest(), context);

    expect(res.status ?? 200).toBe(200);
    expect(res.jsonBody).toEqual({
      mirrored: true,
      heightCm: 182.88,
      measurements: [waist],
      latestWaist: waist,
    });
  });

  test("lists newest-first with a bounded default limit", async () => {
    mirrorV5();
    await handler("bodyMeasurementsList")(makeRequest(), context);

    const [list] = container("bodyMeasurements").queries;
    expect(list.query).toMatch(/ORDER BY c\.recordedAt DESC/);
    expect(list.query).toMatch(/OFFSET 0 LIMIT @limit/);
    expect(list.parameters).toEqual(
      expect.arrayContaining([{ name: "@limit", value: 100 }])
    );
  });

  test("the latest waist ignores the list's filters: the ratio is always current", async () => {
    mirrorV5();
    await handler("bodyMeasurementsList")(
      makeRequest({ site: "hips", startDate: "2026-01-01", endDate: "2026-02-01" }),
      context
    );

    const [, latest] = container("bodyMeasurements").queries;
    expect(latest.query).toMatch(/SELECT TOP 1 \* FROM c WHERE c\.site = @site ORDER BY c\.recordedAt DESC/);
    expect(latest.parameters).toEqual([{ name: "@site", value: "waist" }]);
  });

  test("forwards site and date filters as parameters", async () => {
    mirrorV5();
    await handler("bodyMeasurementsList")(
      makeRequest({ site: "waist", startDate: "2026-10-01", endDate: "2026-11-03", limit: "20" }),
      context
    );

    const [list] = container("bodyMeasurements").queries;
    expect(list.query).toContain("c.site = @site");
    expect(list.query).toContain("c.recordedAt >= @startDate");
    expect(list.query).toContain("c.recordedAt <= @endDate");
    expect(list.parameters).toEqual(
      expect.arrayContaining([
        { name: "@site", value: "waist" },
        { name: "@startDate", value: "2026-10-01T00:00:00.000Z" },
        // A date-only endDate includes that whole (UTC) day.
        { name: "@endDate", value: "2026-11-03T23:59:59.999Z" },
        { name: "@limit", value: 20 },
      ])
    );
  });

  test("normalizes a dated endDate with an offset to UTC so string comparison holds", async () => {
    mirrorV5();
    await handler("bodyMeasurementsList")(
      makeRequest({ endDate: "2026-11-03T10:00:00+01:00" }),
      context
    );
    const [list] = container("bodyMeasurements").queries;
    expect(list.parameters).toEqual(
      expect.arrayContaining([{ name: "@endDate", value: "2026-11-03T09:00:00.000Z" }])
    );
  });

  test("no height on the phone reads as heightCm: null", async () => {
    mirrorV5(null);
    const res = await handler("bodyMeasurementsList")(makeRequest(), context);
    expect((res.jsonBody as { heightCm: unknown }).heightCm).toBeNull();
  });

  test("no waist measurement reads as latestWaist: null", async () => {
    mirrorV5();
    container("bodyMeasurements").queryResults.push([], []);
    const res = await handler("bodyMeasurementsList")(makeRequest(), context);
    expect((res.jsonBody as { latestWaist: unknown }).latestWaist).toBeNull();
  });

  test("strips Cosmos system properties", async () => {
    mirrorV5();
    const withSystem = {
      ...waist,
      _rid: "r",
      _self: "s",
      _etag: "e",
      _attachments: "a",
      _ts: 1,
      _contentHash: "0".repeat(64),
    };
    container("bodyMeasurements").queryResults.push([withSystem], [withSystem]);
    const res = await handler("bodyMeasurementsList")(makeRequest(), context);
    const body = res.jsonBody as { measurements: Doc[]; latestWaist: Doc };
    expect(body.measurements).toEqual([waist]);
    expect(body.latestWaist).toEqual(waist);
  });

  test.each([
    [{ site: "waist; DROP" }],
    [{ site: "" + "x".repeat(40) }],
    [{ startDate: "yesterday" }],
    [{ endDate: "nope" }],
    [{ limit: "0" }],
  ])("rejects %j with 400 before reading", async (query) => {
    const res = await handler("bodyMeasurementsList")(makeRequest(query), context);
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("a Cosmos failure is a 500 that logs no measurement data", async () => {
    mirrorV5();
    container("bodyMeasurements").items.query.mockImplementation(() => ({
      fetchAll: async () => {
        throw new Error("boom");
      },
    }));
    const res = await handler("bodyMeasurementsList")(makeRequest(), context);
    expect(res.status).toBe(500);
    expect(JSON.stringify((context.error as jest.Mock).mock.calls)).not.toContain("86.5");
  });
});

// ─── GET /api/medications ────────────────────────────────────────────────────

describe("GET /api/medications", () => {
  test("lists active medications, excluding archived by default", async () => {
    mirrorV5();
    container("medications").docs.push(vial, tablets);

    const res = await handler("medicationsList")(makeRequest(), context);

    expect(res.status ?? 200).toBe(200);
    expect(res.jsonBody).toEqual({ mirrored: true, medications: [vial] });
  });

  test("a medication without an isArchived flag counts as active", async () => {
    mirrorV5();
    const { isArchived: _omitted, ...unflagged } = vial;
    container("medications").docs.push(unflagged);

    const res = await handler("medicationsList")(makeRequest(), context);

    expect((res.jsonBody as { medications: Doc[] }).medications).toEqual([unflagged]);
  });

  test("includeArchived=true lists every medication, sorted by name ignoring case", async () => {
    mirrorV5();
    container("medications").docs.push(vial, tablets);

    const res = await handler("medicationsList")(
      makeRequest({ includeArchived: "true" }),
      context
    );

    const body = res.jsonBody as { medications: Doc[] };
    expect(body.medications.map((m) => m["name"])).toEqual(["anti-inflammatory", "Vial A"]);
  });

  test("includeArchived must be true or false", async () => {
    const res = await handler("medicationsList")(
      makeRequest({ includeArchived: "yes" }),
      context
    );
    expect(res.status).toBe(400);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });

  test("a Cosmos failure is a 500 that logs no medication data", async () => {
    mirrorV5();
    container("medications").items.query.mockImplementation(() => ({
      fetchAll: async () => {
        throw new Error("boom");
      },
    }));
    const res = await handler("medicationsList")(makeRequest(), context);
    expect(res.status).toBe(500);
    expect(JSON.stringify((context.error as jest.Mock).mock.calls)).not.toContain("Vial A");
  });
});

// ─── GET /api/medication-doses ───────────────────────────────────────────────

describe("GET /api/medication-doses", () => {
  test("returns doses newest-first, each joined to its medication's name", async () => {
    mirrorV5();
    container("medications").docs.push(vial, tablets);
    container("medicationDoses").docs.push(dose);

    const res = await handler("medicationDosesList")(makeRequest(), context);

    expect(res.status ?? 200).toBe(200);
    expect(res.jsonBody).toEqual({
      mirrored: true,
      doses: [{ ...dose, medicationName: "Vial A" }],
    });
    const [query] = container("medicationDoses").queries;
    expect(query.query).toMatch(/ORDER BY c\.takenAt DESC OFFSET 0 LIMIT @limit/);
  });

  test("reports the stored computedMg as logged, never recomputed", async () => {
    // The vial was re-mixed since: its concentration now is 10 mg/mL, but the
    // dose was logged at 5 mg/mL and must still read 2.5 mg.
    mirrorV5();
    container("medications").docs.push({ ...vial, concentrationMgPerMl: 10 });
    container("medicationDoses").docs.push(dose);

    const res = await handler("medicationDosesList")(makeRequest(), context);

    const [served] = (res.jsonBody as { doses: Doc[] }).doses;
    expect(served["computedMg"]).toBe(2.5);
    expect(served["concentrationMgPerMlAtLog"]).toBe(5);
  });

  test("a tablet dose serves its tablet strength at log time, not today's strength", async () => {
    mirrorV5();
    container("medications").docs.push({ ...tablets, tabletStrengthMg: 100 });
    const tabletDose = {
      id: "D-2",
      medicationId: tablets.id,
      takenAt: "2026-11-02T08:00:00.000Z",
      amount: 1.5,
      unit: "tablet",
      computedMg: 75,
      tabletStrengthMgAtLog: 50,
      lastModified: "2026-11-02T08:00:00.000Z",
    };
    container("medicationDoses").docs.push(tabletDose);

    const res = await handler("medicationDosesList")(makeRequest(), context);

    expect((res.jsonBody as { doses: Doc[] }).doses).toEqual([
      { ...tabletDose, medicationName: "anti-inflammatory" },
    ]);
  });

  test("a dose whose medication is gone keeps medicationName null", async () => {
    mirrorV5();
    container("medicationDoses").docs.push({ ...dose, medicationId: "GONE" });

    const res = await handler("medicationDosesList")(makeRequest(), context);

    const [served] = (res.jsonBody as { doses: Doc[] }).doses;
    expect(served["medicationName"]).toBeNull();
  });

  test("filters by medicationId, matching the stored id case-insensitively", async () => {
    mirrorV5();
    container("medications").docs.push(vial);

    await handler("medicationDosesList")(
      makeRequest({ medicationId: vial.id.toLowerCase() }),
      context
    );

    const [query] = container("medicationDoses").queries;
    expect(query.query).toContain("c.medicationId = @medicationId");
    // The stored (upper-case Swift) id is what gets queried.
    expect(query.parameters).toEqual(
      expect.arrayContaining([{ name: "@medicationId", value: vial.id }])
    );
  });

  test("an unknown medicationId is a 404, not an empty log", async () => {
    mirrorV5();
    container("medications").docs.push(vial);

    const res = await handler("medicationDosesList")(
      makeRequest({ medicationId: "NOPE" }),
      context
    );

    expect(res.status).toBe(404);
    expect(container("medicationDoses").queries).toEqual([]);
  });

  test("forwards the date window as UTC bounds on takenAt", async () => {
    mirrorV5();
    await handler("medicationDosesList")(
      makeRequest({ startDate: "2026-11-01", endDate: "2026-11-03", limit: "1000" }),
      context
    );
    const [query] = container("medicationDoses").queries;
    expect(query.query).toContain("c.takenAt >= @startDate");
    expect(query.query).toContain("c.takenAt <= @endDate");
    expect(query.parameters).toEqual(
      expect.arrayContaining([
        { name: "@startDate", value: "2026-11-01T00:00:00.000Z" },
        { name: "@endDate", value: "2026-11-03T23:59:59.999Z" },
        // Clamped to the cap.
        { name: "@limit", value: 500 },
      ])
    );
  });

  test.each([[{ startDate: "soon" }], [{ endDate: "later" }], [{ limit: "-3" }]])(
    "rejects %j with 400 before reading",
    async (query) => {
      const res = await handler("medicationDosesList")(makeRequest(query), context);
      expect(res.status).toBe(400);
      expect(mockDatabase.container).not.toHaveBeenCalled();
    }
  );

  test("a Cosmos failure is a 500 that logs no dose data", async () => {
    mirrorV5();
    container("medications").docs.push(vial);
    container("medicationDoses").items.query.mockImplementation(() => ({
      fetchAll: async () => {
        throw new Error("boom");
      },
    }));
    const res = await handler("medicationDosesList")(makeRequest(), context);
    expect(res.status).toBe(500);
    const logged = JSON.stringify((context.error as jest.Mock).mock.calls);
    expect(logged).not.toContain("Vial A");
    expect(logged).not.toContain("syringeUnits");
  });
});
