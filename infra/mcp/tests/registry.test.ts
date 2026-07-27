/** Tests for the MCP tool registry and inbox write path — issue #88. */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet, apiPost: mockApiPost };
});

const { ApiError } = await import("../src/shared/http.js");
const { TOOLS, handleToolCall } = await import("../src/registry.js");

beforeEach(() => {
  mockApiGet.mockReset();
  mockApiPost.mockReset();
});

describe("tool listing", () => {
  it("exposes the read and inbox-write toolsets with nothing disabled", () => {
    const names = TOOLS.map((t) => t.name).sort();
    expect(names).toEqual(
      [
        "create_custom_exercise",
        "create_program",
        "create_template",
        "delete_template",
        "get_calendar",
        "get_exercise_history",
        "get_stats",
        "get_template",
        "get_workout",
        "health",
        "list_pending_writes",
        "list_templates",
        "list_workouts",
        "search_exercises",
        "update_template",
      ].sort()
    );
  });
});

describe("search_exercises", () => {
  it("returns real bundled exercises and merges matching cloud custom exercises", async () => {
    mockApiGet.mockResolvedValue({
      revision: 3,
      serverTime: "2026-07-27T10:00:00Z",
      snapshot: {
        workouts: [],
        templates: [],
        bodyWeightEntries: [],
        customExercises: [
          {
            id: "custom-uuid",
            externalId: "custom:bench-pullover",
            name: "Bench Pullover",
            primaryMuscles: ["chest"],
            equipment: "dumbbell",
            isCustom: true,
          },
          {
            id: "other-uuid",
            externalId: "custom:standing-calf-bounce",
            name: "Standing Calf Bounce",
            primaryMuscles: ["calves"],
            equipment: null,
            isCustom: true,
          },
        ],
      },
    });

    const result = await handleToolCall("search_exercises", { query: "bench" });

    expect(result.isError).toBeUndefined();
    const exercises = JSON.parse(result.content[0].text);
    expect(exercises).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          externalId: "Bench_Dips",
          name: "Bench Dips",
          primaryMuscles: ["triceps"],
          equipment: "body only",
        }),
        expect.objectContaining({
          externalId: "custom:bench-pullover",
          name: "Bench Pullover",
          primaryMuscles: ["chest"],
          equipment: "dumbbell",
        }),
      ])
    );
    expect(mockApiGet).toHaveBeenCalledWith("sync/snapshot");
  });
});

const benchExercise = {
  externalId: "Barbell_Bench_Press_-_Medium_Grip",
  order: 0,
  defaultSets: 3,
  defaultReps: 8,
  defaultWeight: 80,
  defaultRestSeconds: 120,
  notes: "Pause on chest",
};

describe("inbox write dispatch", () => {
  it("create_template validates a real externalId and posts the wire body", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1", status: "pending" });
    const payload = {
      name: "Push Day",
      notes: "Heavy day",
      exercises: [benchExercise],
    };

    const result = await handleToolCall("create_template", payload);

    expect(result.isError).toBeUndefined();
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "createTemplate",
      payload,
    });
  });

  it("rejects an invented externalId with named suggestions and no HTTP call", async () => {
    const result = await handleToolCall("create_template", {
      name: "Imaginary Day",
      exercises: [
        {
          ...benchExercise,
          externalId: "Totally_Made_Up_Exercise",
        },
      ],
    });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Totally_Made_Up_Exercise");
    expect(result.content[0].text).toMatch(/suggestions?:/i);
    expect(result.content[0].text).toMatch(
      /[A-Za-z]+ [A-Za-z]+.*\([A-Za-z0-9_:-]+\)/
    );
    expect(mockApiGet).not.toHaveBeenCalled();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("create_program validates every template before enqueueing any", async () => {
    const result = await handleToolCall("create_program", {
      templates: [
        {
          name: "Valid Push",
          exercises: [benchExercise],
        },
        {
          name: "Invalid Pull",
          exercises: [
            {
              ...benchExercise,
              externalId: "Totally_Made_Up_Exercise",
            },
          ],
        },
      ],
    });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Totally_Made_Up_Exercise");
    expect(mockApiGet).not.toHaveBeenCalled();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("update_template and delete_template enqueue the right operations", async () => {
    mockApiPost
      .mockResolvedValueOnce({ id: "op-update", status: "pending" })
      .mockResolvedValueOnce({ id: "op-delete", status: "pending" });

    const updatePayload = {
      id: "template-1",
      name: "Push A",
      exercises: [benchExercise],
    };
    const deletePayload = { id: "template-2", name: "Push B" };

    const updateResult = await handleToolCall(
      "update_template",
      updatePayload
    );
    const deleteResult = await handleToolCall(
      "delete_template",
      deletePayload
    );

    expect(updateResult.isError).toBeUndefined();
    expect(deleteResult.isError).toBeUndefined();
    expect(mockApiPost).toHaveBeenNthCalledWith(1, "inbox", {
      op: "updateTemplate",
      payload: updatePayload,
    });
    expect(mockApiPost).toHaveBeenNthCalledWith(2, "inbox", {
      op: "deleteTemplate",
      payload: deletePayload,
    });
  });

  it("create_custom_exercise enqueues the right operation", async () => {
    mockApiPost.mockResolvedValue({ id: "op-custom", status: "pending" });
    const payload = {
      name: "Cable Cross-body Raise",
      equipment: "cable",
      primaryMuscles: ["shoulders"],
      secondaryMuscles: ["traps"],
      instructions: ["Raise across the body."],
      notes: "Keep it strict",
    };

    const result = await handleToolCall("create_custom_exercise", payload);

    expect(result.isError).toBeUndefined();
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "createCustomExercise",
      payload,
    });
  });

  it("list_pending_writes surfaces failed operations and their errors", async () => {
    mockApiGet.mockResolvedValue({
      operations: [
        {
          id: "op-failed",
          op: "createTemplate",
          status: "failed",
          error: "Unresolved externalIds: Missing_Lift",
        },
      ],
    });

    const result = await handleToolCall("list_pending_writes", {
      status: "failed",
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiGet).toHaveBeenCalledWith("inbox", { status: "failed" });
    const operations = JSON.parse(result.content[0].text);
    expect(operations[0].status).toBe("failed");
    expect(operations[0].error).toContain("Missing_Lift");
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
