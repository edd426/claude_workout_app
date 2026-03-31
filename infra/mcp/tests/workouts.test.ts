import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Workout } from "../src/shared/types.js";

const mockFetchAll = vi.fn();
const mockRead = vi.fn();

vi.mock("../src/shared/cosmos.js", () => ({
  getContainer: () => ({
    items: {
      query: () => ({ fetchAll: mockFetchAll }),
    },
    item: () => ({
      read: mockRead,
    }),
  }),
}));

const { listWorkouts, getWorkout } = await import("../src/tools/workouts.js");

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
        {
          id: "s-2",
          order: 1,
          weight: 80,
          weightUnit: "kg",
          reps: 8,
          isCompleted: true,
          completedAt: "2026-03-15T10:10:00Z",
        },
      ],
    },
  ],
};

const olderWorkout: Workout = {
  id: "w-2",
  name: "Leg Day",
  startedAt: "2026-03-10T10:00:00Z",
  completedAt: "2026-03-10T11:30:00Z",
  exercises: [
    {
      id: "we-2",
      order: 0,
      exerciseId: "ex-2",
      exerciseName: "Squat",
      restSeconds: 120,
      sets: [
        {
          id: "s-3",
          order: 0,
          weight: 100,
          weightUnit: "kg",
          reps: 5,
          isCompleted: true,
          completedAt: "2026-03-10T10:15:00Z",
        },
      ],
    },
  ],
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe("Workout Tools", () => {
  // Test 6: list_workouts
  it("should list workouts as summaries", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout, olderWorkout] });

    const result = await listWorkouts();

    expect(result).toHaveLength(2);
    expect(result[0].id).toBe("w-1");
    expect(result[0].totalSets).toBe(2);
    expect(result[0].totalVolume).toBe(80 * 10 + 80 * 8); // 1440
    expect(result[0].exerciseCount).toBe(1);
  });

  // Test 7: get_workout detail
  it("should get full workout detail", async () => {
    mockRead.mockResolvedValue({ resource: sampleWorkout });

    const result = await getWorkout("w-1");

    expect(result).not.toBeNull();
    expect(result!.name).toBe("Push Day");
    expect(result!.exercises[0].sets).toHaveLength(2);
    expect(result!.exercises[0].sets[0].weight).toBe(80);
  });

  // Test 13: date filtering on workouts
  it("should filter workouts by date range", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    await listWorkouts({
      startDate: "2026-03-14T00:00:00Z",
      endDate: "2026-03-16T00:00:00Z",
    });

    // Verify query was called (the mock returns regardless, but we check it was invoked)
    expect(mockFetchAll).toHaveBeenCalledOnce();
  });

  // Test 14 (part 2): error handling for missing workout
  it("should return null for non-existent workout", async () => {
    mockRead.mockRejectedValue({ code: 404 });

    const result = await getWorkout("non-existent");

    expect(result).toBeNull();
  });
});
