import { getContainer } from "../shared/cosmos.js";
import type { Exercise, ExerciseHistoryEntry, Workout } from "../shared/types.js";

export async function searchExercises(options?: {
  name?: string;
  muscle?: string;
  equipment?: string;
  limit?: number;
}): Promise<Exercise[]> {
  const container = getContainer("exercises");
  const conditions: string[] = [];
  const parameters: { name: string; value: string | number }[] = [];

  if (options?.name) {
    conditions.push("CONTAINS(LOWER(c.name), LOWER(@name))");
    parameters.push({ name: "@name", value: options.name });
  }
  if (options?.muscle) {
    conditions.push("ARRAY_CONTAINS(c.primaryMuscles, @muscle)");
    parameters.push({ name: "@muscle", value: options.muscle });
  }
  if (options?.equipment) {
    conditions.push("c.equipment = @equipment");
    parameters.push({ name: "@equipment", value: options.equipment });
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const limit = options?.limit ?? 50;

  const query = `SELECT * FROM c ${where} ORDER BY c.name OFFSET 0 LIMIT @limit`;
  parameters.push({ name: "@limit", value: limit });

  const { resources } = await container.items
    .query({ query, parameters })
    .fetchAll();

  return resources as Exercise[];
}

export async function getExerciseHistory(
  exerciseId: string,
  options?: { limit?: number },
): Promise<ExerciseHistoryEntry[]> {
  const container = getContainer("workouts");
  const limit = options?.limit ?? 20;

  // Fetch recent workouts and filter for ones containing this exercise
  const query = `SELECT * FROM c ORDER BY c.startedAt DESC OFFSET 0 LIMIT @limit`;
  const { resources } = await container.items
    .query({ query, parameters: [{ name: "@limit", value: limit * 3 }] })
    .fetchAll();

  const entries: ExerciseHistoryEntry[] = [];
  for (const workout of resources as Workout[]) {
    for (const ex of workout.exercises) {
      if (ex.exerciseId === exerciseId) {
        entries.push({
          workoutId: workout.id,
          workoutName: workout.name,
          date: workout.startedAt,
          sets: ex.sets,
        });
      }
    }
  }

  return entries.slice(0, limit);
}
