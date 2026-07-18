/**
 * Read-only template tools — issue #79.
 * Thin wrappers over the Functions API. Write operations (create/update/
 * delete) are disabled until the write path is redesigned.
 */

import { apiGet, ApiError } from "../shared/http.js";
import type { WorkoutTemplate } from "../shared/types.js";

export async function listTemplates(): Promise<WorkoutTemplate[]> {
  const { templates } = await apiGet<{ templates: WorkoutTemplate[] }>(
    "templates"
  );
  return templates;
}

export async function getTemplate(id: string): Promise<WorkoutTemplate | null> {
  try {
    return await apiGet<WorkoutTemplate>(
      `templates/${encodeURIComponent(id)}`
    );
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}
