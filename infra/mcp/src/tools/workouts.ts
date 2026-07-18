/**
 * Read-only workout tools — issue #79.
 * Thin wrappers over the Functions API.
 */

import { apiGet, ApiError } from "../shared/http.js";
import type { Workout, WorkoutSummary } from "../shared/types.js";

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
  return workouts;
}

export async function getWorkout(id: string): Promise<Workout | null> {
  try {
    return await apiGet<Workout>(`workouts/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}
