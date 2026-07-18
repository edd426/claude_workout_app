/**
 * Tests for workout read endpoints — issue #79
 *
 * GET /api/workouts        — list workout summaries with date filtering (bounded)
 * GET /api/workouts/{id}   — full workout detail
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import {
  mockItems,
  mockItemRead,
  mockFetchAll,
  resetCosmosDb,
} from "./__mocks__/cosmos";
import "../src/functions/workouts";

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

const sampleWorkout = {
  id: "w-1",
  templateId: "tmpl-1",
  name: "Push Day",
  startedAt: "2026-03-15T10:00:00Z",
  completedAt: "2026-03-15T11:00:00Z",
  exercises: [
    {
      id: "we-1",
      order: 0,
      exerciseId: "ex-1",
      exerciseName: "Bench Press",
      restSeconds: 90,
      sets: [
        {
          id: "s-1",
          order: 0,
          weight: 80,
          weightUnit: "kg",
          reps: 10,
          isCompleted: true,
          completedAt: "2026-03-15T10:05:00Z",
        },
        {
          id: "s-2",
          order: 1,
          weight: 80,
          weightUnit: "kg",
          reps: 8,
          isCompleted: true,
          completedAt: "2026-03-15T10:10:00Z",
        },
        {
          id: "s-3",
          order: 2,
          weight: 85,
          weightUnit: "kg",
          reps: 5,
          isCompleted: false,
        },
      ],
    },
  ],
};

beforeEach(() => {
  mockItems.query.mockClear();
  mockFetchAll.mockClear();
  mockItemRead.mockClear();
  resetCosmosDb();
  mockAuthenticate.mockReturnValue(null);
});

describe("GET /api/workouts — list", () => {
  test("registers with GET method and workouts route", () => {
    const reg = findRegistration("workoutsList");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("workouts");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("workoutsList")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(401);
    expect(mockItems.query).not.toHaveBeenCalled();
  });

  test("returns workout summaries with computed sets and volume", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    const res = await findHandler("workoutsList")(makeRequest(), new InvocationContext());

    expect(res.status ?? 200).toBe(200);
    const body = res.jsonBody as { workouts: Record<string, unknown>[] };
    expect(body.workouts).toHaveLength(1);
    expect(body.workouts[0]).toEqual({
      id: "w-1",
      templateId: "tmpl-1",
      name: "Push Day",
      startedAt: "2026-03-15T10:00:00Z",
      completedAt: "2026-03-15T11:00:00Z",
      exerciseCount: 1,
      totalSets: 2, // only completed sets count
      totalVolume: 80 * 10 + 80 * 8,
    });
  });

  test("applies startDate and endDate filters as query parameters", async () => {
    await findHandler("workoutsList")(
      makeRequest({
        query: {
          startDate: "2026-03-01T00:00:00Z",
          endDate: "2026-03-31T00:00:00Z",
        },
      }),
      new InvocationContext()
    );

    const [queryArg] = mockItems.query.mock.calls[0];
    expect(queryArg.query).toContain("c.startedAt >= @startDate");
    expect(queryArg.query).toContain("c.startedAt <= @endDate");
    expect(queryArg.parameters).toEqual(
      expect.arrayContaining([
        { name: "@startDate", value: "2026-03-01T00:00:00Z" },
        { name: "@endDate", value: "2026-03-31T00:00:00Z" },
      ])
    );
  });

  test("rejects an invalid startDate with 400", async () => {
    const res = await findHandler("workoutsList")(
      makeRequest({ query: { startDate: "not-a-date" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(400);
    expect(mockItems.query).not.toHaveBeenCalled();
  });

  test("rejects a non-numeric limit with 400", async () => {
    const res = await findHandler("workoutsList")(
      makeRequest({ query: { limit: "lots" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(400);
  });

  test("caps limit at 200", async () => {
    await findHandler("workoutsList")(
      makeRequest({ query: { limit: "5000" } }),
      new InvocationContext()
    );
    const [queryArg] = mockItems.query.mock.calls[0];
    const limitParam = queryArg.parameters.find(
      (p: { name: string }) => p.name === "@limit"
    );
    expect(limitParam.value).toBe(200);
  });

  test("defaults limit to 50", async () => {
    await findHandler("workoutsList")(makeRequest(), new InvocationContext());
    const [queryArg] = mockItems.query.mock.calls[0];
    const limitParam = queryArg.parameters.find(
      (p: { name: string }) => p.name === "@limit"
    );
    expect(limitParam.value).toBe(50);
  });

  test("returns 500 when Cosmos fails", async () => {
    mockFetchAll.mockRejectedValue(new Error("boom"));
    const res = await findHandler("workoutsList")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(500);
  });
});

describe("GET /api/workouts/{id} — detail", () => {
  test("registers with GET method and workouts/{id} route", () => {
    const reg = findRegistration("workoutsGet");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("workouts/{id}");
  });

  test("returns the full workout when found", async () => {
    mockItemRead.mockResolvedValue({ resource: sampleWorkout });

    const res = await findHandler("workoutsGet")(
      makeRequest({ params: { id: "w-1" } }),
      new InvocationContext()
    );

    expect(res.status ?? 200).toBe(200);
    expect(res.jsonBody).toEqual(sampleWorkout);
  });

  test("returns 404 when not found", async () => {
    mockItemRead.mockResolvedValue({ resource: undefined });

    const res = await findHandler("workoutsGet")(
      makeRequest({ params: { id: "missing" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(404);
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("workoutsGet")(
      makeRequest({ params: { id: "w-1" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(401);
  });
});
