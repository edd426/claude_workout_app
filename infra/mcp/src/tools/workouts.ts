/**
 * Read-only workout tools — issue #79.
 * Thin wrappers over the Functions API.
 */

import { apiGet, ApiError } from "../shared/http.js";
import type { Workout, WorkoutSummary } from "../shared/types.js";

/**
 * #143: the phone pushes in-progress sessions for crash resilience, so a
 * workout without `completedAt` is a draft, not a Finish that failed. Label it
 * so no reader has to infer that (it produced the false alarm in #139).
 */
function markDraft<T extends { completedAt?: string | null }>(w: T): T & { isDraft: boolean } {
  return { ...w, isDraft: !w.completedAt };
}

export async function listWorkouts(options?: {
  startDate?: string;
  endDate?: string;
  limit?: number;
}): Promise<WorkoutSummary[]> {
  const { workouts } = await apiGet<{ workouts: WorkoutSummary[] }>(
    "workouts",
    {
      startDate: options?.startDate,
      endDate: options?.endDate,
      limit: options?.limit,
    }
  );
  return workouts.map(markDraft);
}

export async function getWorkout(id: string): Promise<Workout | null> {
  try {
    return markDraft(await apiGet<Workout>(`workouts/${encodeURIComponent(id)}`));
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}
