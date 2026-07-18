/**
 * Tests for read-only stats + calendar tools — issue #79.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Stats, CalendarEntry } from "../src/shared/types.js";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { getStats, getCalendar } = await import("../src/tools/stats.js");

const sampleStats: Stats = {
  totalWorkouts: 12,
  totalSets: 144,
  totalVolume: 98000,
  workoutsPerWeek: 3.2,
  personalRecords: [
    {
      exerciseId: "ex-1",
      exerciseName: "Bench Press",
      type: "heaviest_weight",
      value: 100,
      date: "2026-03-15T10:00:00Z",
    },
  ],
  muscleGroupDistribution: {},
};

const sampleDays: CalendarEntry[] = [
  { date: "2026-03-15", workoutCount: 1, totalSets: 12, totalVolume: 8000 },
];

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("getStats", () => {
  it("fetches GET stats with optional date filters", async () => {
    mockApiGet.mockResolvedValue(sampleStats);

    const result = await getStats({
      startDate: "2026-01-01T00:00:00Z",
      endDate: "2026-03-31T00:00:00Z",
    });

    expect(mockApiGet).toHaveBeenCalledWith("stats", {
      startDate: "2026-01-01T00:00:00Z",
      endDate: "2026-03-31T00:00:00Z",
    });
    expect(result.totalWorkouts).toBe(12);
    expect(result.personalRecords[0].value).toBe(100);
  });

  it("works without date filters", async () => {
    mockApiGet.mockResolvedValue(sampleStats);

    await getStats();

    expect(mockApiGet).toHaveBeenCalledWith("stats", {
      startDate: undefined,
      endDate: undefined,
    });
  });
});

describe("getCalendar", () => {
  it("fetches GET calendar with required dates and unwraps days", async () => {
    mockApiGet.mockResolvedValue({ days: sampleDays });

    const result = await getCalendar("2026-03-01", "2026-03-31");

    expect(mockApiGet).toHaveBeenCalledWith("calendar", {
      startDate: "2026-03-01",
      endDate: "2026-03-31",
    });
    expect(result).toHaveLength(1);
    expect(result[0].date).toBe("2026-03-15");
  });
});
