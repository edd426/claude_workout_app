import { describe, it, expect, vi, beforeEach } from "vitest";
import type { WorkoutTemplate, TemplateExercise } from "../src/shared/types.js";

// Mock the cosmos module before importing tools
const mockFetchAll = vi.fn();
const mockRead = vi.fn();
const mockCreate = vi.fn();
const mockReplace = vi.fn();
const mockDelete = vi.fn();

vi.mock("../src/shared/cosmos.js", () => ({
  getContainer: () => ({
    items: {
      query: () => ({ fetchAll: mockFetchAll }),
      create: mockCreate,
    },
    item: () => ({
      read: mockRead,
      replace: mockReplace,
      delete: mockDelete,
    }),
  }),
}));

const { listTemplates, getTemplate, createTemplate, updateTemplate, deleteTemplate } =
  await import("../src/tools/templates.js");

const sampleExercise: TemplateExercise = {
  id: "te-1",
  order: 0,
  exerciseId: "ex-1",
  exerciseName: "Bench Press",
  defaultSets: 3,
  defaultReps: 10,
  defaultWeight: 60,
  defaultRestSeconds: 90,
};

const sampleTemplate: WorkoutTemplate = {
  id: "tmpl-1",
  name: "Push Day",
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:00Z",
  timesPerformed: 5,
  exercises: [sampleExercise],
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe("Template Tools", () => {
  // Test 1: list_templates
  it("should list all templates", async () => {
    mockFetchAll.mockResolvedValue({ resources: [sampleTemplate] });

    const result = await listTemplates();

    expect(result).toHaveLength(1);
    expect(result[0].name).toBe("Push Day");
  });

  // Test 2: get_template returns template
  it("should get a template by ID", async () => {
    mockRead.mockResolvedValue({ resource: sampleTemplate });

    const result = await getTemplate("tmpl-1");

    expect(result).not.toBeNull();
    expect(result!.name).toBe("Push Day");
    expect(result!.exercises).toHaveLength(1);
  });

  // Test 3: create_template
  it("should create a new template", async () => {
    mockCreate.mockResolvedValue({ resource: { ...sampleTemplate, id: "new-id" } });

    const result = await createTemplate("Leg Day", [sampleExercise]);

    expect(mockCreate).toHaveBeenCalledOnce();
    const created = mockCreate.mock.calls[0][0];
    expect(created.name).toBe("Leg Day");
    expect(created.exercises[0].order).toBe(0);
    expect(created.timesPerformed).toBe(0);
  });

  // Test 4: update_template
  it("should update an existing template", async () => {
    mockRead.mockResolvedValue({ resource: sampleTemplate });
    mockReplace.mockResolvedValue({
      resource: { ...sampleTemplate, name: "Pull Day" },
    });

    const result = await updateTemplate("tmpl-1", { name: "Pull Day" });

    expect(result).not.toBeNull();
    expect(mockReplace).toHaveBeenCalledOnce();
    const replaced = mockReplace.mock.calls[0][0];
    expect(replaced.name).toBe("Pull Day");
  });

  // Test 5: delete_template
  it("should delete a template", async () => {
    mockDelete.mockResolvedValue({});

    const result = await deleteTemplate("tmpl-1");

    expect(result).toBe(true);
    expect(mockDelete).toHaveBeenCalledOnce();
  });

  // Test 14: error handling for missing template
  it("should return null for non-existent template", async () => {
    mockRead.mockRejectedValue({ code: 404 });

    const result = await getTemplate("non-existent");

    expect(result).toBeNull();
  });

  // Test 15: input validation - create requires exercises
  it("should create template with exercise ordering", async () => {
    const exercises: TemplateExercise[] = [
      { ...sampleExercise, id: "te-1", exerciseName: "Bench Press" },
      { ...sampleExercise, id: "te-2", exerciseName: "Incline Press" },
      { ...sampleExercise, id: "te-3", exerciseName: "Flyes" },
    ];
    mockCreate.mockResolvedValue({ resource: sampleTemplate });

    await createTemplate("Push Day", exercises);

    const created = mockCreate.mock.calls[0][0];
    expect(created.exercises[0].order).toBe(0);
    expect(created.exercises[1].order).toBe(1);
    expect(created.exercises[2].order).toBe(2);
  });
});
