import { getContainer } from "../shared/cosmos.js";
import type { WorkoutTemplate, TemplateExercise } from "../shared/types.js";

export async function listTemplates(): Promise<WorkoutTemplate[]> {
  const container = getContainer("templates");
  const { resources } = await container.items
    .query("SELECT * FROM c ORDER BY c.name")
    .fetchAll();
  return resources as WorkoutTemplate[];
}

export async function getTemplate(id: string): Promise<WorkoutTemplate | null> {
  try {
    const container = getContainer("templates");
    const { resource } = await container.item(id, id).read();
    return (resource as WorkoutTemplate) ?? null;
  } catch (err: unknown) {
    if (isNotFound(err)) return null;
    throw err;
  }
}

export async function createTemplate(
  name: string,
  exercises: TemplateExercise[],
  notes?: string,
): Promise<WorkoutTemplate> {
  const container = getContainer("templates");
  const now = new Date().toISOString();
  const template: WorkoutTemplate = {
    id: crypto.randomUUID(),
    name,
    notes,
    createdAt: now,
    updatedAt: now,
    timesPerformed: 0,
    exercises: exercises.map((e, i) => ({ ...e, order: i })),
  };
  const { resource } = await container.items.create(template);
  return resource as WorkoutTemplate;
}

export async function updateTemplate(
  id: string,
  updates: Partial<Pick<WorkoutTemplate, "name" | "notes" | "exercises">>,
): Promise<WorkoutTemplate | null> {
  const existing = await getTemplate(id);
  if (!existing) return null;

  const updated: WorkoutTemplate = {
    ...existing,
    ...updates,
    updatedAt: new Date().toISOString(),
  };
  if (updates.exercises) {
    updated.exercises = updates.exercises.map((e, i) => ({ ...e, order: i }));
  }

  const container = getContainer("templates");
  const { resource } = await container.item(id, id).replace(updated);
  return resource as WorkoutTemplate;
}

export async function deleteTemplate(id: string): Promise<boolean> {
  try {
    const container = getContainer("templates");
    await container.item(id, id).delete();
    return true;
  } catch (err: unknown) {
    if (isNotFound(err)) return false;
    throw err;
  }
}

function isNotFound(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code: number }).code === 404
  );
}
