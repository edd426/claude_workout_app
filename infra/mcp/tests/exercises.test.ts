import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Exercise, Workout } from "../src/shared/types.js";

const mockFetchAll = vi.fn();

vi.mock("../src/shared/cosmos.js", () => ({
  getContainer: () => ({
    items: {
      query: () => ({ fetchAll: mockFetchAll }),
    },
  }),
}));

const { searchExercises, getExerciseHistory } = await import(
  "../src/tools/exercises.js"
);
const { getStats, getCalendar } = await import("../src/tools/stats.js");
const { createProgram } = await import("../src/tools/programs.js");

// Need to also mock templates for createProgram
const mockCreate = vi.fn();
vi.mock("../src/shared/cosmos.js", async () => ({
  getContainer: () => ({
    items: {
      query: () => ({ fetchAll: mockFetchAll }),
      create: mockCreate,
    },
    item: () => ({
      read: vi.fn().mockResolvedValue({ resource: null }),
      replace: vi.fn(),
      delete: vi.fn(),
    }),
  }),
}));

const sampleExercise: Exercise = {
  id: "ex-1",
  name: "Bench Press",
  force: "push",
  level: "intermediate",
  mechanic: "compound",
  equipment: "barbell",
  isCustom: false,
  primaryMuscles: ["chest"],
  secondaryMuscles: ["triceps", "shoulders"],
};

const sampleWorkout: Workout = {
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
          weightUnit: "kg" as const,
          reps: 10,
          isCompleted: true,
          completedAt: "2026-03-15T10:05:00Z",
        },
        {
          id: "s-2",
          order: 1,
          weight: 85,
          weightUnit: "kg" as const,
          reps: 8,
          isCompleted: true,
          completedAt: "2026-03-15T10:10:00Z",
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
          weightUnit: "kg" as const,
          reps: 12,
          isCompleted: true,
          completedAt: "2026-03-15T10:20:00Z",
        },
      ],
    },
  ],
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe("Exercise Tools", () => {
  // Test 8: exercise history
  it("should return exercise history from workouts", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    const result = await getExerciseHistory("ex-1");

    expect(result).toHaveLength(1);
    expect(result[0].workoutName).toBe("Push Day");
    expect(result[0].sets).toHaveLength(2);
  });

  // Test 9: search exercises
  it("should search exercises by name", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleExercise] });

    const result = await searchExercises({ name: "bench" });

    expect(result).toHaveLength(1);
    expect(result[0].name).toBe("Bench Press");
    expect(mockFetchAll).toHaveBeenCalledOnce();
  });
});

describe("Stats Tools", () => {
  // Test 10: stats aggregation
  it("should compute stats from workouts", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    const result = await getStats();

    expect(result.totalWorkouts).toBe(1);
    expect(result.totalSets).toBe(3); // 2 bench + 1 shoulder
    // Volume: 80*10 + 85*8 + 40*12 = 800 + 680 + 480 = 1960
    expect(result.totalVolume).toBe(1960);
    expect(result.personalRecords.length).toBeGreaterThan(0);
  });

  // Test 11: calendar
  it("should return calendar entries grouped by day", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleWorkout] });

    const result = await getCalendar("2026-03-01", "2026-03-31");

    expect(result).toHaveLength(1);
    expect(result[0].date).toBe("2026-03-15");
    expect(result[0].workoutCount).toBe(1);
    expect(result[0].totalSets).toBe(3);
  });
});

describe("Program Tools", () => {
  // Test 12: create program
  it("should create multiple templates for a program", async () => {
    mockCreate.mockResolvedValue({
      resource: {
        id: "new-tmpl",
        name: "PPL - Push Day",
        createdAt: "2026-03-15T00:00:00Z",
        updatedAt: "2026-03-15T00:00:00Z",
        timesPerformed: 0,
        exercises: [],
      },
    });

    const result = await createProgram("PPL", [
      {
        name: "Push Day",
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
      },
      {
        name: "Pull Day",
        exercises: [
          {
            id: "te-2",
            order: 0,
            exerciseId: "ex-2",
            exerciseName: "Barbell Row",
            defaultSets: 3,
            defaultReps: 10,
            defaultRestSeconds: 90,
          },
        ],
      },
    ]);

    expect(result).toHaveLength(2);
    expect(mockCreate).toHaveBeenCalledTimes(2);
    // Verify program name is prefixed
    const firstCall = mockCreate.mock.calls[0][0];
    expect(firstCall.name).toBe("PPL - Push Day");
  });
});
