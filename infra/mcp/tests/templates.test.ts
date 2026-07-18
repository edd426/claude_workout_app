/**
 * Tests for read-only template tools — issue #79.
 * Tools are thin wrappers over the Functions API HTTP client.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { WorkoutTemplate } from "../src/shared/types.js";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { ApiError } = await import("../src/shared/http.js");
const { listTemplates, getTemplate } = await import("../src/tools/templates.js");

const sampleTemplate: WorkoutTemplate = {
  id: "tmpl-1",
  name: "Push Day",
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:00Z",
  timesPerformed: 5,
  exercises: [
    {
      id: "te-1",
      order: 0,
      exerciseId: "ex-1",
      exerciseName: "Bench Press",
      defaultSets: 3,
      defaultReps: 10,
      defaultWeight: 60,
      defaultRestSeconds: 90,
    },
  ],
};

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("listTemplates", () => {
  it("fetches GET templates and unwraps the templates array", async () => {
    mockApiGet.mockResolvedValue({ templates: [sampleTemplate] });

    const result = await listTemplates();

    expect(mockApiGet).toHaveBeenCalledWith("templates");
    expect(result).toHaveLength(1);
    expect(result[0].name).toBe("Push Day");
  });
});

describe("getTemplate", () => {
  it("fetches GET templates/{id}", async () => {
    mockApiGet.mockResolvedValue(sampleTemplate);

    const result = await getTemplate("tmpl-1");

    expect(mockApiGet).toHaveBeenCalledWith("templates/tmpl-1");
    expect(result).not.toBeNull();
    expect(result!.exercises).toHaveLength(1);
  });

  it("URL-encodes the id", async () => {
    mockApiGet.mockResolvedValue(sampleTemplate);
    await getTemplate("a/b c");
    expect(mockApiGet).toHaveBeenCalledWith("templates/a%2Fb%20c");
  });

  it("returns null on 404", async () => {
    mockApiGet.mockRejectedValue(new ApiError(404, "Template not found: nope"));
    const result = await getTemplate("nope");
    expect(result).toBeNull();
  });

  it("rethrows non-404 errors", async () => {
    mockApiGet.mockRejectedValue(new ApiError(500, "server exploded"));
    await expect(getTemplate("tmpl-1")).rejects.toThrow("server exploded");
  });
});
