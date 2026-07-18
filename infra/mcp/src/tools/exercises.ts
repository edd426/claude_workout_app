/**
 * Read-only exercise-history tool — issue #79.
 *
 * search_exercises has been removed: the app never syncs the exercise
 * library to the cloud, so the exercises container is empty and searches
 * would silently return nothing. See the registry for the explanatory error.
 */

import { apiGet } from "../shared/http.js";
import type { ExerciseHistoryEntry } from "../shared/types.js";

export async function getExerciseHistory(
  exerciseId: string,
  options?: { limit?: number }
): Promise<ExerciseHistoryEntry[]> {
  const { entries } = await apiGet<{
    exerciseId: string;
    entries: ExerciseHistoryEntry[];
  }>(`exercises/${encodeURIComponent(exerciseId)}/history`, {
    limit: options?.limit,
  });
  return entries;
}
