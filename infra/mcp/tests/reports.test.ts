/**
 * Tests for the exercise-report tools — issue #135.
 * Thin wrappers over the Functions API: a read and a durable inbox write.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet, apiPost: mockApiPost };
});

const { listExerciseReports, resolveExerciseReport } = await import(
  "../src/tools/reports.js"
);

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
  mockApiGet.mockReset();
  mockApiPost.mockReset();
});

describe("listExerciseReports", () => {
  it("returns the backlog and forwards every filter", async () => {
    mockApiGet.mockResolvedValue({ reports: [sampleReport] });

    const reports = await listExerciseReports({
      status: "open",
      category: "wrongExercise",
      exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
      limit: 25,
    });

    expect(reports).toEqual([sampleReport]);
    expect(mockApiGet).toHaveBeenCalledWith("reports", {
      status: "open",
      category: "wrongExercise",
      exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
      limit: 25,
    });
  });

  it("sends no status by default, letting the server pick the live backlog", async () => {
    mockApiGet.mockResolvedValue({ reports: [] });

    await listExerciseReports();

    expect(mockApiGet).toHaveBeenCalledWith("reports", {
      status: undefined,
      category: undefined,
      exerciseExternalId: undefined,
      limit: undefined,
    });
  });

  it("rejects an unknown status without calling the API", async () => {
    await expect(listExerciseReports({ status: "closed" })).rejects.toThrow(
      /Unknown report status/
    );
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("rejects an unknown category without calling the API", async () => {
    await expect(
      listExerciseReports({ category: "featureRequest" })
    ).rejects.toThrow(/Unknown report category/);
    expect(mockApiGet).not.toHaveBeenCalled();
  });
});

describe("resolveExerciseReport", () => {
  it("enqueues an inbox operation", async () => {
    mockApiPost.mockResolvedValue({
      id: "op-1",
      op: "resolveExerciseReport",
      status: "pending",
      requiresApproval: false,
    });

    const operation = await resolveExerciseReport({
      id: "r-1",
      resolution: "Filed as #140",
    });

    expect(operation.status).toBe("pending");
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "resolveExerciseReport",
      payload: { id: "r-1", status: undefined, resolution: "Filed as #140" },
    });
  });

  it("accepts acknowledged for work that is known but not done", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    await resolveExerciseReport({ id: "r-1", status: "acknowledged" });

    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "resolveExerciseReport",
      payload: { id: "r-1", status: "acknowledged", resolution: undefined },
    });
  });

  it("refuses to reopen a report", async () => {
    await expect(
      resolveExerciseReport({ id: "r-1", status: "open" })
    ).rejects.toThrow(/cannot be reopened/);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("requires an id", async () => {
    await expect(resolveExerciseReport({ resolution: "done" })).rejects.toThrow(
      /id must be a non-empty string/
    );
    expect(mockApiPost).not.toHaveBeenCalled();
  });
});
