/**
 * Tests for stats + calendar read endpoints — issue #79
 *
 * GET /api/stats     — summary statistics (PRs, volume, frequency), bounded scan
 * GET /api/calendar  — per-day workout frequency for a date range
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import { mockItems, mockFetchAll, resetCosmosDb } from "./__mocks__/cosmos";
import "../src/functions/stats";

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
        },
        {
          id: "s-2",
          order: 1,
          weight: 85,
          weightUnit: "kg",
          reps: 8,
          isCompleted: true,
        },
      ],
    },
    {
      id: "we-2",
      order: 1,
      exerciseId: "ex-3",
      exerciseName: "Shoulder Press",
      restSeconds: 90,
      sets: [
        {
          id: "s-3",
          order: 0,
          weight: 40,
          weightUnit: "kg",
          reps: 12,
          isCompleted: true,
        },
      ],
    },
  ],
};

beforeEach(() => {
  mockItems.query.mockClear();
  mockFetchAll.mockClear();
  resetCosmosDb();
  mockAuthenticate.mockReturnValue(null);
});

describe("GET /api/stats", () => {
  test("registers with GET method and stats route", () => {
    const reg = findRegistration("stats");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("stats");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("stats")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(401);
  });

  test("computes totals and PRs from workouts", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    const res = await findHandler("stats")(makeRequest(), new InvocationContext());

    expect(res.status ?? 200).toBe(200);
    const body = res.jsonBody as {
      totalWorkouts: number;
      totalSets: number;
      totalVolume: number;
      personalRecords: { exerciseId: string; value: number }[];
    };
    expect(body.totalWorkouts).toBe(1);
    expect(body.totalSets).toBe(3);
    // 80*10 + 85*8 + 40*12 = 1960
    expect(body.totalVolume).toBe(1960);
    const benchPR = body.personalRecords.find((pr) => pr.exerciseId === "ex-1");
    expect(benchPR).toBeDefined();
    expect(benchPR!.value).toBe(85);
  });

  test("rejects an invalid endDate with 400", async () => {
    const res = await findHandler("stats")(
      makeRequest({ query: { endDate: "yesterday-ish" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(400);
  });

  test("bounds the workout scan with a LIMIT", async () => {
    await findHandler("stats")(makeRequest(), new InvocationContext());
    const [queryArg] = mockItems.query.mock.calls[0];
    expect(queryArg.query).toContain("LIMIT");
    const limitParam = queryArg.parameters.find(
      (p: { name: string }) => p.name === "@limit"
    );
    expect(limitParam).toBeDefined();
    expect(limitParam.value).toBeLessThanOrEqual(500);
  });

  test("returns 500 when Cosmos fails", async () => {
    mockFetchAll.mockRejectedValue(new Error("boom"));
    const res = await findHandler("stats")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(500);
  });
});

describe("GET /api/calendar", () => {
  test("registers with GET method and calendar route", () => {
    const reg = findRegistration("calendar");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("calendar");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("calendar")(
      makeRequest({
        query: {
          startDate: "2026-03-01T00:00:00Z",
          endDate: "2026-03-31T00:00:00Z",
        },
      }),
      new InvocationContext()
    );
    expect(res.status).toBe(401);
  });

  test("requires startDate and endDate", async () => {
    const res = await findHandler("calendar")(makeRequest(), new InvocationContext());
    expect(res.status).toBe(400);
  });

  test("rejects invalid dates with 400", async () => {
    const res = await findHandler("calendar")(
      makeRequest({ query: { startDate: "bad", endDate: "2026-03-31T00:00:00Z" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(400);
  });

  test("groups workouts into per-day entries", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    const res = await findHandler("calendar")(
      makeRequest({
        query: {
          startDate: "2026-03-01T00:00:00Z",
          endDate: "2026-03-31T00:00:00Z",
        },
      }),
      new InvocationContext()
    );

    expect(res.status ?? 200).toBe(200);
    const body = res.jsonBody as { days: Record<string, unknown>[] };
    expect(body.days).toHaveLength(1);
    expect(body.days[0]).toEqual({
      date: "2026-03-15",
      workoutCount: 1,
      totalSets: 3,
      totalVolume: 1960,
    });
  });

  test("returns 500 when Cosmos fails", async () => {
    mockFetchAll.mockRejectedValue(new Error("boom"));
    const res = await findHandler("calendar")(
      makeRequest({
        query: {
          startDate: "2026-03-01T00:00:00Z",
          endDate: "2026-03-31T00:00:00Z",
        },
      }),
      new InvocationContext()
    );
    expect(res.status).toBe(500);
  });
});
