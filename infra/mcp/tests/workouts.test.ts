/**
 * Tests for read-only workout tools — issue #79.
 * Tools are thin wrappers over the Functions API HTTP client.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Workout, WorkoutSummary } from "../src/shared/types.js";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { ApiError } = await import("../src/shared/http.js");
const { listWorkouts, getWorkout } = await import("../src/tools/workouts.js");

const sampleSummary: WorkoutSummary = {
  id: "w-1",
  templateId: "tmpl-1",
  name: "Push Day",
  startedAt: "2026-03-15T10:00:00Z",
  completedAt: "2026-03-15T11:00:00Z",
  exerciseCount: 1,
  totalSets: 2,
  totalVolume: 1440,
};

const sampleWorkout: Workout = {
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
      ],
    },
  ],
};

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("listWorkouts", () => {
  it("fetches GET workouts and unwraps the summaries", async () => {
    mockApiGet.mockResolvedValue({ workouts: [sampleSummary] });

    const result = await listWorkouts();

    expect(mockApiGet).toHaveBeenCalledWith("workouts", {
      startDate: undefined,
      endDate: undefined,
      limit: undefined,
    });
    expect(result).toHaveLength(1);
    expect(result[0].totalVolume).toBe(1440);
  });

  it("passes date filters and limit through as query params", async () => {
    mockApiGet.mockResolvedValue({ workouts: [] });

    await listWorkouts({
      startDate: "2026-03-01T00:00:00Z",
      endDate: "2026-03-31T00:00:00Z",
      limit: 10,
    });

    expect(mockApiGet).toHaveBeenCalledWith("workouts", {
      startDate: "2026-03-01T00:00:00Z",
      endDate: "2026-03-31T00:00:00Z",
      limit: 10,
    });
  });
});

describe("getWorkout", () => {
  it("fetches GET workouts/{id}", async () => {
    mockApiGet.mockResolvedValue(sampleWorkout);

    const result = await getWorkout("w-1");

    expect(mockApiGet).toHaveBeenCalledWith("workouts/w-1");
    expect(result).not.toBeNull();
    expect(result!.exercises[0].sets[0].weight).toBe(80);
  });

  it("returns null on 404", async () => {
    mockApiGet.mockRejectedValue(new ApiError(404, "Workout not found: nope"));
    const result = await getWorkout("nope");
    expect(result).toBeNull();
  });

  it("rethrows non-404 errors", async () => {
    mockApiGet.mockRejectedValue(new ApiError(401, "Unauthorized"));
    await expect(getWorkout("w-1")).rejects.toThrow("Unauthorized");
  });
});
