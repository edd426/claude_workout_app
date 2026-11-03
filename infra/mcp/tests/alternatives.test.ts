/**
 * Tests for template-exercise alternatives on the MCP write tools — issue #169.
 *
 * `alternatives: [{ externalId, note? }]` per exercise on create_template,
 * update_template and create_program. Every alternative externalId is
 * validated against the catalog exactly like the main exercise, before any
 * POST. The key is tri-state on the phone (absent keeps the slot's list, []
 * clears it, a list replaces it), so an absent key must stay absent in the
 * payload, never become [].
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet, apiPost: mockApiPost };
});

const { handleToolCall, TOOLS } = await import("../src/registry.js");
const { getTemplate } = await import("../src/tools/templates.js");

const squat = {
  externalId: "Barbell_Squat",
  order: 0,
  defaultSets: 3,
  defaultReps: 5,
};

type Payload = { exercises: Record<string, unknown>[] };

function postedPayload(call = 0): Payload {
  return (mockApiPost.mock.calls[call][1] as { payload: Payload }).payload;
}

beforeEach(() => {
  mockApiGet.mockReset();
  mockApiPost.mockReset();
  mockApiPost.mockResolvedValue({ id: "op-1", status: "pending" });
});

describe("alternatives on template writes (#169)", () => {
  it("create_template sends validated alternatives in order, as {externalId, note?}", async () => {
    const result = await handleToolCall("create_template", {
      name: "Legs",
      exercises: [
        {
          ...squat,
          alternatives: [
            { externalId: "Leg_Press", note: "if the rack is taken" },
            { externalId: "Smith_Machine_Squat" },
          ],
        },
      ],
    });

    expect(result.isError).toBeUndefined();
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "createTemplate",
      payload: {
        name: "Legs",
        exercises: [
          {
            ...squat,
            alternatives: [
              { externalId: "Leg_Press", note: "if the rack is taken" },
              { externalId: "Smith_Machine_Squat" },
            ],
          },
        ],
      },
    });
  });

  it("an absent alternatives key stays absent in the payload (keeps the slot's list)", async () => {
    await handleToolCall("update_template", { id: "T-1", exercises: [squat] });

    expect(postedPayload().exercises[0]).not.toHaveProperty("alternatives");
  });

  it("an empty list is sent as [] (clears the slot's list)", async () => {
    await handleToolCall("update_template", {
      id: "T-1",
      exercises: [{ ...squat, alternatives: [] }],
    });

    expect(postedPayload().exercises[0]["alternatives"]).toEqual([]);
  });

  it("an invented alternative externalId is refused with suggestions and nothing is posted", async () => {
    const result = await handleToolCall("create_template", {
      name: "Legs",
      exercises: [{ ...squat, alternatives: [{ externalId: "Hack_Squat_Machine_9000" }] }],
    });

    expect(result.isError).toBe(true);
    expect(result.content[0].type === "text" && result.content[0].text).toMatch(
      /Unknown externalId "Hack_Squat_Machine_9000"/
    );
    expect(result.content[0].type === "text" && result.content[0].text).toMatch(
      /exercises\[0\]\.alternatives\[0\]/
    );
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("a synced custom exercise can be an alternative", async () => {
    const customId = "custom:belt-squat:10000000-0000-4000-8000-000000000008";
    mockApiGet.mockResolvedValue({
      snapshot: {
        customExercises: [
          {
            id: "10000000-0000-4000-8000-000000000008",
            externalId: customId,
            name: "Belt Squat",
            primaryMuscles: ["quadriceps"],
          },
        ],
      },
    });

    const result = await handleToolCall("create_template", {
      name: "Legs",
      exercises: [{ ...squat, alternatives: [{ externalId: customId }] }],
    });

    expect(result.isError).toBeUndefined();
    expect(postedPayload().exercises[0]["alternatives"]).toEqual([{ externalId: customId }]);
  });

  it.each([
    ["null (ambiguous between keep and clear)", null, /omit it to keep/],
    ["an object", { externalId: "Leg_Press" }, /must be an array/],
    ["a bare string entry", ["Leg_Press"], /must be an object/],
    ["an entry without externalId", [{ note: "x" }], /externalId must be a non-empty string/],
    ["a non-string note", [{ externalId: "Leg_Press", note: 4 }], /note must be a string/],
  ])("refuses alternatives that are %s", async (_label, alternatives, message) => {
    const result = await handleToolCall("create_template", {
      name: "Legs",
      exercises: [{ ...squat, alternatives }],
    });

    expect(result.isError).toBe(true);
    expect(result.content[0].type === "text" && result.content[0].text).toMatch(message);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("drops keys the phone does not read from each alternative", async () => {
    await handleToolCall("create_template", {
      name: "Legs",
      exercises: [
        { ...squat, alternatives: [{ externalId: "Leg_Press", order: 9, name: "Leg Press" }] },
      ],
    });

    expect(postedPayload().exercises[0]["alternatives"]).toEqual([{ externalId: "Leg_Press" }]);
  });

  it("create_program validates every template's alternatives before posting any", async () => {
    const result = await handleToolCall("create_program", {
      templates: [
        { name: "Day 1", exercises: [{ ...squat, alternatives: [{ externalId: "Leg_Press" }] }] },
        { name: "Day 2", exercises: [{ ...squat, alternatives: [{ externalId: "Nope_Not_Real" }] }] },
      ],
    });

    expect(result.isError).toBe(true);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("create_program carries alternatives through on success", async () => {
    await handleToolCall("create_program", {
      templates: [
        { name: "Day 1", exercises: [{ ...squat, alternatives: [{ externalId: "Leg_Press" }] }] },
        { name: "Day 2", exercises: [squat] },
      ],
    });

    expect(mockApiPost).toHaveBeenCalledTimes(2);
    expect(postedPayload(0).exercises[0]["alternatives"]).toEqual([{ externalId: "Leg_Press" }]);
    expect(postedPayload(1).exercises[0]).not.toHaveProperty("alternatives");
  });

  it("the template exercise schema documents the tri-state semantics", () => {
    const create = TOOLS.find((tool) => tool.name === "update_template");
    const exercises = (create?.inputSchema.properties as Record<string, { items: { properties: Record<string, { description?: string }> } }>)["exercises"];
    const description = exercises.items.properties["alternatives"].description ?? "";
    expect(description).toMatch(/omit/i);
    expect(description).toMatch(/\[\] clears/);
  });
});

describe("get_template with alternatives (#169)", () => {
  it("names each bundled alternative from the catalog and keeps the mirror's order", async () => {
    mockApiGet.mockResolvedValue({
      id: "T-1",
      name: "Legs",
      createdAt: "x",
      updatedAt: "x",
      timesPerformed: 0,
      exercises: [
        {
          id: "TE-1",
          order: 0,
          exerciseId: "ex-1",
          exerciseName: "Barbell Squat",
          defaultSets: 3,
          defaultReps: 5,
          defaultRestSeconds: 180,
          alternatives: [
            { externalId: "Leg_Press", order: 0, note: "if the rack is taken" },
            { externalId: "custom:belt-squat:10000000-0000-4000-8000-000000000008", order: 1 },
          ],
        },
      ],
    });

    const template = await getTemplate("T-1");

    expect(template?.exercises[0].alternatives).toEqual([
      { externalId: "Leg_Press", order: 0, note: "if the rack is taken", name: "Leg Press" },
      { externalId: "custom:belt-squat:10000000-0000-4000-8000-000000000008", order: 1 },
    ]);
  });

  it("leaves a template without alternatives (not yet mirrored) unchanged", async () => {
    const template = {
      id: "T-2",
      name: "Push",
      createdAt: "x",
      updatedAt: "x",
      timesPerformed: 0,
      exercises: [
        {
          id: "TE-1",
          order: 0,
          exerciseId: "ex-1",
          exerciseName: "Bench",
          defaultSets: 3,
          defaultReps: 5,
          defaultRestSeconds: 120,
        },
      ],
    };
    mockApiGet.mockResolvedValue(template);

    expect(await getTemplate("T-2")).toEqual(template);
  });
});
