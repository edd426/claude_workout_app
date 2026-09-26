/**
 * Tests for the exercise-report read endpoint — issue #135.
 *
 * GET /api/reports — the complaint backlog the phone filed, filterable.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import { mockItems, mockFetchAll, resetCosmosDb } from "./__mocks__/cosmos";
import "../src/functions/reports";

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

function makeRequest(options?: { query?: Record<string, string> }) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(undefined, { "x-api-key": "test-key" }, options);
}

function lastQuery(): { query: string; parameters: { name: string; value: unknown }[] } {
  const call = mockItems.query.mock.calls.at(-1);
  if (!call) throw new Error("No Cosmos query was issued");
  return call[0];
}

const sampleReport = {
  id: "r-1",
  createdAt: "2026-08-18T10:00:00Z",
  category: "wrongExercise",
  detail: "This is really the iso-lateral press",
  exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
  exerciseName: "Barbell Bench Press",
  suggestedReplacement: "Hammer Strength Iso-Lateral Press",
  status: "open",
  lastModified: "2026-08-18T10:00:00Z",
};

beforeEach(() => {
  mockItems.query.mockClear();
  mockFetchAll.mockClear();
  resetCosmosDb();
  mockAuthenticate.mockReturnValue(null);
});

describe("GET /api/reports", () => {
  test("registers with GET method and reports route", () => {
    const reg = findRegistration("reportsList");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("reports");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("reportsList")(
      makeRequest(),
      new InvocationContext()
    );
    expect(res.status).toBe(401);
    expect(mockItems.query).not.toHaveBeenCalled();
  });

  test("returns the reports newest-first", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleReport] });

    const res = await findHandler("reportsList")(
      makeRequest(),
      new InvocationContext()
    );

    expect(res.status ?? 200).toBe(200);
    expect((res.jsonBody as { reports: unknown[] }).reports).toEqual([sampleReport]);
    expect(lastQuery().query).toContain("ORDER BY c.createdAt DESC");
  });

  test("defaults to everything not yet resolved, not just status=open", async () => {
    // Acknowledged reports are still outstanding work — dropping them would
    // make the default view lie about the size of the backlog.
    await findHandler("reportsList")(makeRequest(), new InvocationContext());

    const { query, parameters } = lastQuery();
    expect(query).toContain("c.status != @resolved");
    expect(parameters).toContainEqual({ name: "@resolved", value: "resolved" });
  });

  test("filters by status, category, and exercise together", async () => {
    await findHandler("reportsList")(
      makeRequest({
        query: {
          status: "acknowledged",
          category: "bug",
          exerciseExternalId: "squat",
        },
      }),
      new InvocationContext()
    );

    const { query, parameters } = lastQuery();
    expect(query).toContain("c.status = @status");
    expect(query).toContain("c.category = @category");
    expect(query).toContain("c.exerciseExternalId = @exerciseExternalId");
    expect(parameters).toContainEqual({ name: "@status", value: "acknowledged" });
    expect(parameters).toContainEqual({ name: "@category", value: "bug" });
    expect(parameters).toContainEqual({
      name: "@exerciseExternalId",
      value: "squat",
    });
  });

  test("status=all drops the status filter entirely", async () => {
    await findHandler("reportsList")(
      makeRequest({ query: { status: "all" } }),
      new InvocationContext()
    );

    const { query } = lastQuery();
    expect(query).not.toContain("c.status");
  });

  test("rejects an unknown status without querying", async () => {
    const res = await findHandler("reportsList")(
      makeRequest({ query: { status: "closed" } }),
      new InvocationContext()
    );

    expect(res.status).toBe(400);
    expect(mockItems.query).not.toHaveBeenCalled();
  });

  test("caps the limit", async () => {
    await findHandler("reportsList")(
      makeRequest({ query: { limit: "9000" } }),
      new InvocationContext()
    );

    expect(lastQuery().parameters).toContainEqual({ name: "@limit", value: 500 });
  });

  test("returns 500 when Cosmos fails", async () => {
    mockFetchAll.mockRejectedValue(new Error("cosmos down"));

    const res = await findHandler("reportsList")(
      makeRequest(),
      new InvocationContext()
    );

    expect(res.status).toBe(500);
  });
});
