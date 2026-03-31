import { createTemplate } from "./templates.js";
import type { WorkoutTemplate, TemplateExercise } from "../shared/types.js";

export interface ProgramTemplate {
  name: string;
  notes?: string;
  exercises: TemplateExercise[];
}

export async function createProgram(
  name: string,
  templates: ProgramTemplate[],
): Promise<WorkoutTemplate[]> {
  const created: WorkoutTemplate[] = [];
  for (const t of templates) {
    const template = await createTemplate(
      `${name} - ${t.name}`,
      t.exercises,
      t.notes,
    );
    created.push(template);
  }
  return created;
}
