/**
 * Tests for GET /api/exercises/{exerciseId}/history — issue #79
 *
 * Returns per-exercise history entries (sets across past workouts),
 * bounded by a limit param. Backs the MCP get_exercise_history tool.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import { mockItems, mockFetchAll, resetCosmosDb } from "./__mocks__/cosmos";
import "../src/functions/exerciseHistory";

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

const benchSets = [
  {
    id: "s-1",
    order: 0,
    weight: 80,
    weightUnit: "kg",
    reps: 10,
    isCompleted: true,
    completedAt: "2026-03-15T10:05:00Z",
  },
];

const workoutWithBench = {
  id: "w-1",
  name: "Push Day",
  startedAt: "2026-03-15T10:00:00Z",
  exercises: [
    {
      id: "we-1",
      order: 0,
      exerciseId: "ex-1",
      exerciseName: "Bench Press",
      restSeconds: 90,
      sets: benchSets,
    },
  ],
};

const workoutWithoutBench = {
  id: "w-2",
  name: "Leg Day",
  startedAt: "2026-03-10T10:00:00Z",
  exercises: [
    {
      id: "we-2",
      order: 0,
      exerciseId: "ex-2",
      exerciseName: "Squat",
      restSeconds: 120,
      sets: [
        {
          id: "s-2",
          order: 0,
          weight: 100,
          weightUnit: "kg",
          reps: 5,
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

describe("GET /api/exercises/{exerciseId}/history", () => {
  test("registers with GET method and exercises/{exerciseId}/history route", () => {
    const reg = findRegistration("exerciseHistory");
    expect(reg.methods).toEqual(["GET"]);
    expect(reg.route).toBe("exercises/{exerciseId}/history");
  });

  test("requires authentication", async () => {
    mockAuthenticate.mockReturnValue({ status: 401, jsonBody: { error: "no" } });
    const res = await findHandler("exerciseHistory")(
      makeRequest({ params: { exerciseId: "ex-1" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(401);
  });

  test("returns only workouts containing the requested exercise", async () => {
    mockFetchAll.mockResolvedValue({
      resources: [workoutWithBench, workoutWithoutBench],
    });

    const res = await findHandler("exerciseHistory")(
      makeRequest({ params: { exerciseId: "ex-1" } }),
      new InvocationContext()
    );

    expect(res.status ?? 200).toBe(200);
    const body = res.jsonBody as {
      exerciseId: string;
      entries: Record<string, unknown>[];
    };
    expect(body.exerciseId).toBe("ex-1");
    expect(body.entries).toHaveLength(1);
    expect(body.entries[0]).toEqual({
      workoutId: "w-1",
      workoutName: "Push Day",
      date: "2026-03-15T10:00:00Z",
      sets: benchSets,
    });
  });

  test("rejects a non-numeric limit with 400", async () => {
    const res = await findHandler("exerciseHistory")(
      makeRequest({ params: { exerciseId: "ex-1" }, query: { limit: "nope" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(400);
  });

  test("bounds the underlying workout scan even for large limits", async () => {
    await findHandler("exerciseHistory")(
      makeRequest({ params: { exerciseId: "ex-1" }, query: { limit: "99999" } }),
      new InvocationContext()
    );
    const [queryArg] = mockItems.query.mock.calls[0];
    const limitParam = queryArg.parameters.find(
      (p: { name: string }) => p.name === "@limit"
    );
    // Scan cap: never fetch unbounded history from Cosmos
    expect(limitParam.value).toBeLessThanOrEqual(300);
  });

  test("truncates entries to the requested limit", async () => {
    const manyWorkouts = Array.from({ length: 5 }, (_, i) => ({
      ...workoutWithBench,
      id: `w-${i}`,
      startedAt: `2026-03-1${i}T10:00:00Z`,
    }));
    mockFetchAll.mockResolvedValue({ resources: manyWorkouts });

    const res = await findHandler("exerciseHistory")(
      makeRequest({ params: { exerciseId: "ex-1" }, query: { limit: "2" } }),
      new InvocationContext()
    );

    const body = res.jsonBody as { entries: unknown[] };
    expect(body.entries).toHaveLength(2);
  });

  test("returns 500 when Cosmos fails", async () => {
    mockFetchAll.mockRejectedValue(new Error("boom"));
    const res = await findHandler("exerciseHistory")(
      makeRequest({ params: { exerciseId: "ex-1" } }),
      new InvocationContext()
    );
    expect(res.status).toBe(500);
  });
});
