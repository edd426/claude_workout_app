/** Tests for the MCP tool registry and inbox write path — issue #88. */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();
const mockApiDelete = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return {
    ...actual,
    apiGet: mockApiGet,
    apiPost: mockApiPost,
    apiDelete: mockApiDelete,
  };
});

const { ApiError } = await import("../src/shared/http.js");
const { TOOLS, handleToolCall } = await import("../src/registry.js");

beforeEach(() => {
  mockApiGet.mockReset();
  mockApiPost.mockReset();
  mockApiDelete.mockReset();
});

describe("tool listing", () => {
  it("exposes the read and inbox-write toolsets with nothing disabled", () => {
    const names = TOOLS.map((t) => t.name).sort();
    expect(names).toEqual(
      [
        "create_custom_exercise",
        "create_program",
        "create_template",
        "delete_inbox_operation",
        "delete_template",
        "get_calendar",
        "get_exercise_history",
        "get_report_photo",
        "get_stats",
        "get_template",
        "get_workout",
        "health",
        "list_exercise_reports",
        "list_pending_writes",
        "list_templates",
        "list_workouts",
        "resolve_exercise_report",
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
            id: "10000000-0000-4000-8000-000000000008",
            externalId:
              "custom:bench-pullover:10000000-0000-4000-8000-000000000008",
            name: "Bench Pullover",
            primaryMuscles: ["chest"],
            equipment: "dumbbell",
            isCustom: true,
          },
          {
            id: "10000000-0000-4000-8000-000000000009",
            externalId:
              "custom:standing-calf-bounce:10000000-0000-4000-8000-000000000009",
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
          externalId:
            "custom:bench-pullover:10000000-0000-4000-8000-000000000008",
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

  it("resolves a synced custom externalId before enqueueing a template", async () => {
    const externalId =
      "custom:deja-vu-row:10000000-0000-4000-8000-000000000006";
    mockApiGet.mockResolvedValue({
      snapshot: {
        customExercises: [
          {
            id: "10000000-0000-4000-8000-000000000006",
            externalId,
            name: "Déjà Vu Row",
            primaryMuscles: ["back"],
            equipment: "cable",
          },
        ],
      },
    });
    mockApiPost.mockResolvedValue({ id: "template-op", status: "pending" });
    const payload = {
      name: "Custom Pull",
      exercises: [{ ...benchExercise, externalId }],
    };

    const result = await handleToolCall("create_template", payload);

    expect(result.isError).toBeUndefined();
    expect(mockApiGet).toHaveBeenCalledWith("sync/snapshot");
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "createTemplate",
      payload,
    });
  });

  it("accepts a custom externalId with a 64-character slug", async () => {
    const id = "10000000-0000-4000-8000-000000000010";
    const externalId = `custom:${"a".repeat(64)}:${id}`;
    mockApiGet.mockResolvedValue({
      snapshot: {
        customExercises: [
          {
            id,
            externalId,
            name: "Maximum Slug",
            primaryMuscles: [],
            equipment: null,
          },
        ],
      },
    });
    mockApiPost.mockResolvedValue({ id: "template-op", status: "pending" });

    const result = await handleToolCall("create_template", {
      name: "Maximum Slug Template",
      exercises: [{ ...benchExercise, externalId }],
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiPost).toHaveBeenCalledTimes(1);
  });

  it("rejects the shared invalid custom externalId cases before enqueueing", async () => {
    const operationId = "10000000-0000-4000-8000-000000000001";
    const invalidExternalIds = [
      "custom:",
      "custom:row",
      `custom:Bad_Slug:${operationId}`,
      `custom:${"a".repeat(65)}:${operationId}`,
      "custom:row:00000000-0000-4000-8000-000000000000",
    ];

    for (const externalId of invalidExternalIds) {
      mockApiGet.mockReset();
      mockApiPost.mockReset();
      mockApiGet.mockResolvedValue({
        snapshot: {
          customExercises: [
            {
              id: operationId,
              externalId,
              name: "Invalid Custom Exercise",
              primaryMuscles: [],
              equipment: null,
            },
          ],
        },
      });

      const result = await handleToolCall("create_template", {
        name: "Invalid Custom Identity",
        exercises: [{ ...benchExercise, externalId }],
      });

      expect(result.isError).toBe(true);
      expect(result.content[0].text).toContain("externalId");
      expect(mockApiPost).not.toHaveBeenCalled();
    }
  });

  it("resolves a custom externalId from its pending durable inbox operation", async () => {
    const externalId =
      "custom:pending-row:10000000-0000-4000-8000-000000000007";
    mockApiGet.mockImplementation(
      async (endpoint: string, options?: { status?: string }) => {
        if (endpoint === "sync/snapshot") {
          return { snapshot: { customExercises: [] } };
        }
        if (endpoint === "inbox" && options?.status === "pending") {
          return {
            operations: [
              {
                id: "10000000-0000-4000-8000-000000000007",
                op: "createCustomExercise",
                status: "pending",
                payload: { name: "Pending Row", externalId },
              },
            ],
          };
        }
        return { operations: [] };
      }
    );
    mockApiPost.mockResolvedValue({ id: "template-op", status: "pending" });

    const result = await handleToolCall("create_template", {
      name: "Immediate Custom Pull",
      exercises: [{ ...benchExercise, externalId }],
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiGet).toHaveBeenCalledWith("inbox", {
      status: "pending",
    });
    expect(mockApiPost).toHaveBeenCalledTimes(1);
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

  it("delete_inbox_operation deletes a single terminal operation", async () => {
    mockApiDelete.mockResolvedValue(undefined);

    const result = await handleToolCall("delete_inbox_operation", {
      id: "f4c9187b",
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiDelete).toHaveBeenCalledWith("inbox/f4c9187b");
    expect(JSON.parse(result.content[0].text)).toEqual({
      deleted: ["f4c9187b"],
    });
  });

  it("delete_inbox_operation deletes a batch of ids", async () => {
    mockApiDelete.mockResolvedValue(undefined);

    const result = await handleToolCall("delete_inbox_operation", {
      ids: ["ff69a245", "b365dd1b", "d26f588a"],
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiDelete).toHaveBeenCalledTimes(3);
    expect(JSON.parse(result.content[0].text)).toEqual({
      deleted: ["ff69a245", "b365dd1b", "d26f588a"],
    });
  });

  it("delete_inbox_operation surfaces the Functions API's 409 for a pending operation", async () => {
    mockApiDelete.mockRejectedValue(
      new ApiError(409, "Cannot delete pending createTemplate operation op-1")
    );

    const result = await handleToolCall("delete_inbox_operation", {
      id: "op-1",
    });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Cannot delete pending");
  });

  it("delete_inbox_operation surfaces an unknown id as a tool error", async () => {
    mockApiDelete.mockRejectedValue(
      new ApiError(404, "Inbox operation not found: nope")
    );

    const result = await handleToolCall("delete_inbox_operation", {
      id: "nope",
    });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("not found");
  });

  it("delete_inbox_operation rejects an empty batch without calling the API", async () => {
    const result = await handleToolCall("delete_inbox_operation", {
      ids: [],
    });

    expect(result.isError).toBe(true);
    expect(mockApiDelete).not.toHaveBeenCalled();
  });
});

describe("get_report_photo (issue #141)", () => {
  const REPORT_ID = "6E4B1C2A-9D3F-4E21-8A7B-0C1D2E3F4A5B";
  const PHOTO_PATH = `reports/${REPORT_ID}.jpg`;
  const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  const report = {
    id: REPORT_ID,
    createdAt: "2026-09-20T18:00:00Z",
    category: "wrongExercise",
    detail: "This machine is the iso-lateral press, not a bench",
    exerciseName: "Barbell Bench Press",
    status: "open",
    photoURL: PHOTO_PATH,
    lastModified: "2026-09-20T18:00:00Z",
  };
  const mockFetch = vi.fn();

  function serve(reports: unknown[]) {
    mockApiGet.mockImplementation(async (path: string) => {
      if (path === "reports") return { reports };
      if (path === "images/sas") {
        return {
          sasUrl: `https://teststorage.blob.core.windows.net/workout-images/${PHOTO_PATH}?sig=x`,
          expiresAt: "2026-09-25T07:00:00Z",
        };
      }
      throw new Error(`unexpected apiGet(${path})`);
    });
  }

  beforeEach(() => {
    mockFetch.mockReset();
    mockFetch.mockImplementation(async () => new Response(JPEG));
    vi.stubGlobal("fetch", mockFetch);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns a caption naming the report, then the photo as MCP image content", async () => {
    serve([report]);

    const result = await handleToolCall("get_report_photo", { id: REPORT_ID });

    expect(result.isError).toBeUndefined();
    expect(result.content).toHaveLength(2);
    const [caption, image] = result.content;
    expect(caption.type).toBe("text");
    expect(caption.type === "text" && caption.text).toContain(
      "Barbell Bench Press"
    );
    expect(image).toEqual({
      type: "image",
      data: Buffer.from(JPEG).toString("base64"),
      mimeType: "image/jpeg",
    });
  });

  it("a report without a photo is an informational text result, not an error", async () => {
    serve([{ ...report, photoURL: null }]);

    const result = await handleToolCall("get_report_photo", { id: REPORT_ID });

    expect(result.isError).toBeUndefined();
    expect(result.content).toHaveLength(1);
    const [only] = result.content;
    expect(only.type).toBe("text");
    // Plain prose, not a JSON-quoted string.
    expect(only.type === "text" && only.text).toMatch(/^Report /);
    expect(only.type === "text" && only.text).toMatch(/not uploaded yet/);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it("surfaces an unknown report as a tool error", async () => {
    serve([]);

    const result = await handleToolCall("get_report_photo", { id: REPORT_ID });

    expect(result.isError).toBe(true);
    expect(result.content[0].type === "text" && result.content[0].text).toContain(
      "Report not found"
    );
  });

  it("requires an id argument", async () => {
    const result = await handleToolCall("get_report_photo", {});

    expect(result.isError).toBe(true);
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("list_exercise_reports tells the model how to view an attached photo", () => {
    const list = TOOLS.find((t) => t.name === "list_exercise_reports");
    expect(list?.description).toContain("photoURL");
    expect(list?.description).toContain("get_report_photo");
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
