/**
 * Tests for the MCP tool registry — issue #79.
 *
 * Read-only ship: 7 read tools + health are exposed. Write tools
 * (create_template, update_template, delete_template, create_program) are
 * hard-disabled with a clear error referencing issue #79, and
 * search_exercises explains that the exercise library is not synced.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { ApiError } = await import("../src/shared/http.js");
const { TOOLS, handleToolCall } = await import("../src/registry.js");

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("tool listing", () => {
  it("exposes exactly the read-only toolset plus health", () => {
    const names = TOOLS.map((t) => t.name).sort();
    expect(names).toEqual(
      [
        "get_calendar",
        "get_exercise_history",
        "get_stats",
        "get_template",
        "get_workout",
        "health",
        "list_templates",
        "list_workouts",
      ].sort()
    );
  });

  it("does not list write tools or search_exercises", () => {
    const names = TOOLS.map((t) => t.name);
    for (const removed of [
      "create_template",
      "update_template",
      "delete_template",
      "create_program",
      "search_exercises",
    ]) {
      expect(names).not.toContain(removed);
    }
  });
});

describe("disabled write tools", () => {
  it.each([
    "create_template",
    "update_template",
    "delete_template",
    "create_program",
  ])("%s returns a clear disabled error referencing #79", async (name) => {
    const result = await handleToolCall(name, {});

    expect(result.isError).toBe(true);
    const text = result.content[0].text;
    expect(text).toMatch(/read-only/i);
    expect(text).toContain("#79");
    expect(mockApiGet).not.toHaveBeenCalled();
  });
});

describe("search_exercises", () => {
  it("explains the exercise library is not synced instead of returning empty results", async () => {
    const result = await handleToolCall("search_exercises", { name: "bench" });

    expect(result.isError).toBe(true);
    const text = result.content[0].text;
    expect(text).toMatch(/exercise library/i);
    expect(text).toMatch(/not synced/i);
    expect(mockApiGet).not.toHaveBeenCalled();
  });
});

describe("read tool dispatch", () => {
  it("list_templates returns templates as JSON text", async () => {
    mockApiGet.mockResolvedValue({
      templates: [{ id: "tmpl-1", name: "Push Day" }],
    });

    const result = await handleToolCall("list_templates", {});

    expect(result.isError).toBeUndefined();
    const parsed = JSON.parse(result.content[0].text);
    expect(parsed[0].name).toBe("Push Day");
  });

  it("get_template surfaces not-found as a tool error", async () => {
    mockApiGet.mockRejectedValue(new ApiError(404, "Template not found: nope"));

    const result = await handleToolCall("get_template", { id: "nope" });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Template not found: nope");
  });

  it("get_workout surfaces not-found as a tool error", async () => {
    mockApiGet.mockRejectedValue(new ApiError(404, "Workout not found: nope"));

    const result = await handleToolCall("get_workout", { id: "nope" });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Workout not found: nope");
  });

  it("get_template requires an id argument", async () => {
    const result = await handleToolCall("get_template", {});
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toMatch(/id/);
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("get_calendar requires startDate and endDate", async () => {
    const result = await handleToolCall("get_calendar", {});
    expect(result.isError).toBe(true);
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("get_exercise_history dispatches with exerciseId and limit", async () => {
    mockApiGet.mockResolvedValue({ exerciseId: "ex-1", entries: [] });

    const result = await handleToolCall("get_exercise_history", {
      exerciseId: "ex-1",
      limit: 5,
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiGet).toHaveBeenCalledWith("exercises/ex-1/history", {
      limit: 5,
    });
  });

  it("API errors surface as tool errors, not crashes", async () => {
    mockApiGet.mockRejectedValue(new ApiError(500, "Failed to list workouts"));

    const result = await handleToolCall("list_workouts", {});

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Failed to list workouts");
  });

  it("unknown tools return an error", async () => {
    const result = await handleToolCall("does_not_exist", {});
    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Unknown tool");
  });
});
