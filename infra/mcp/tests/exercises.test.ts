/**
 * Tests for the read-only exercise-history tool — issue #79.
 *
 * search_exercises has been removed (the app never syncs the exercise library,
 * so the exercises container is empty — see registry.test.ts for the
 * explanatory error). Only get_exercise_history remains here.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ExerciseHistoryEntry } from "../src/shared/types.js";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { getExerciseHistory } = await import("../src/tools/exercises.js");

const sampleEntry: ExerciseHistoryEntry = {
  workoutId: "w-1",
  workoutName: "Push Day",
  date: "2026-03-15T10:00:00Z",
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
};

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("getExerciseHistory", () => {
  it("fetches GET exercises/{exerciseId}/history and unwraps entries", async () => {
    mockApiGet.mockResolvedValue({ exerciseId: "ex-1", entries: [sampleEntry] });

    const result = await getExerciseHistory("ex-1");

    expect(mockApiGet).toHaveBeenCalledWith("exercises/ex-1/history", {
      limit: undefined,
    });
    expect(result).toHaveLength(1);
    expect(result[0].workoutName).toBe("Push Day");
    expect(result[0].sets).toHaveLength(1);
  });

  it("passes the limit through as a query param", async () => {
    mockApiGet.mockResolvedValue({ exerciseId: "ex-1", entries: [] });

    await getExerciseHistory("ex-1", { limit: 5 });

    expect(mockApiGet).toHaveBeenCalledWith("exercises/ex-1/history", {
      limit: 5,
    });
  });

  it("URL-encodes the exercise id", async () => {
    mockApiGet.mockResolvedValue({ exerciseId: "a b", entries: [] });
    await getExerciseHistory("a b");
    expect(mockApiGet).toHaveBeenCalledWith("exercises/a%20b/history", {
      limit: undefined,
    });
  });
});
