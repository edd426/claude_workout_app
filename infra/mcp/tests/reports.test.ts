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

  // Reopening was refused outright until #146. The case that changed it:
  // #136's prescribed fix was acknowledged, shipped, and turned out to be
  // inert. With no way back, a real complaint had left the backlog for good.
  it("reopens a report that was closed too early", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    await resolveExerciseReport({
      id: "r-1",
      status: "open",
      resolution: "Reopened — the fix did not touch this case",
    });

    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "resolveExerciseReport",
      payload: {
        id: "r-1",
        status: "open",
        resolution: "Reopened — the fix did not touch this case",
      },
    });
  });

  it("rejects a status that is not part of the lifecycle", async () => {
    await expect(
      resolveExerciseReport({ id: "r-1", status: "wontfix" })
    ).rejects.toThrow(/status must be one of/);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  // Closing out a gym session means answering several reports at once, and
  // one call per report is three round trips plus three chances to lose track.
  it("closes several reports in one call", async () => {
    mockApiPost.mockResolvedValue({ id: "op-n" });

    const operations = await resolveExerciseReport({
      ids: ["r-1", "r-2", "r-3"],
      status: "acknowledged",
      resolution: "All three fixed in 1.4.1",
    });

    expect(Array.isArray(operations)).toBe(true);
    expect(operations).toHaveLength(3);
    expect(mockApiPost).toHaveBeenCalledTimes(3);
    expect(mockApiPost).toHaveBeenNthCalledWith(2, "inbox", {
      op: "resolveExerciseReport",
      payload: {
        id: "r-2",
        status: "acknowledged",
        resolution: "All three fixed in 1.4.1",
      },
    });
  });

  it("a single id still returns one operation, not an array", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    const result = await resolveExerciseReport({ id: "r-1" });

    expect(Array.isArray(result)).toBe(false);
  });

  it("rejects ids and id given together rather than guessing", async () => {
    await expect(
      resolveExerciseReport({ id: "r-1", ids: ["r-2"] })
    ).rejects.toThrow(/either id or ids/);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("rejects an empty ids array", async () => {
    await expect(resolveExerciseReport({ ids: [] })).rejects.toThrow(
      /at least one/
    );
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("validates every id before enqueuing any of them", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    await expect(
      resolveExerciseReport({ ids: ["r-1", ""] })
    ).rejects.toThrow(/non-empty string/);
    // Nothing enqueued: a half-applied batch is worse than a refused one.
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("requires an id", async () => {
    await expect(resolveExerciseReport({ resolution: "done" })).rejects.toThrow(
      /id must be a non-empty string/
    );
    expect(mockApiPost).not.toHaveBeenCalled();
  });
});
