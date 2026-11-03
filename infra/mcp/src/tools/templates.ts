/** Read-side template tools. Inbox write tools live in writes.ts. */

import { apiGet, ApiError } from "../shared/http.js";
import type { WorkoutTemplate } from "../shared/types.js";
import { findExerciseByExternalId } from "./catalog.js";

export async function listTemplates(): Promise<WorkoutTemplate[]> {
  const { templates } = await apiGet<{ templates: WorkoutTemplate[] }>(
    "templates"
  );
  return templates;
}

export async function getTemplate(id: string): Promise<WorkoutTemplate | null> {
  let template: WorkoutTemplate;
  try {
    template = await apiGet<WorkoutTemplate>(
      `templates/${encodeURIComponent(id)}`
    );
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
  return withAlternativeNames(template);
}

/**
 * Issue #169. The mirror stores an alternative by externalId only; name the
 * bundled ones from the catalog so the template reads without a lookup per
 * alternative. Custom (`custom:`) ids are left unnamed rather than fetched.
 */
function withAlternativeNames(template: WorkoutTemplate): WorkoutTemplate {
  if (!Array.isArray(template.exercises)) return template;
  return {
    ...template,
    exercises: template.exercises.map((exercise) =>
      Array.isArray(exercise.alternatives)
        ? {
            ...exercise,
            alternatives: exercise.alternatives.map((alternative) => {
              const name = findExerciseByExternalId(alternative.externalId)?.name;
              return name === undefined ? alternative : { ...alternative, name };
            }),
          }
        : exercise
    ),
  };
}
