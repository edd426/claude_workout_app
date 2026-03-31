import { getContainer } from "../shared/cosmos.js";
import type { Workout, WorkoutSummary } from "../shared/types.js";

export async function listWorkouts(options?: {
  startDate?: string;
  endDate?: string;
  limit?: number;
}): Promise<WorkoutSummary[]> {
  const container = getContainer("workouts");
  const conditions: string[] = [];
  const parameters: { name: string; value: string | number }[] = [];

  if (options?.startDate) {
    conditions.push("c.startedAt >= @startDate");
    parameters.push({ name: "@startDate", value: options.startDate });
  }
  if (options?.endDate) {
    conditions.push("c.startedAt <= @endDate");
    parameters.push({ name: "@endDate", value: options.endDate });
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const limit = options?.limit ?? 50;

  const query = `SELECT * FROM c ${where} ORDER BY c.startedAt DESC OFFSET 0 LIMIT @limit`;
  parameters.push({ name: "@limit", value: limit });

  const { resources } = await container.items
    .query({ query, parameters })
    .fetchAll();

  return (resources as Workout[]).map(toSummary);
}

export async function getWorkout(id: string): Promise<Workout | null> {
  try {
    const container = getContainer("workouts");
    const { resource } = await container.item(id, id).read();
    return (resource as Workout) ?? null;
  } catch (err: unknown) {
    if (isNotFound(err)) return null;
    throw err;
  }
}

function toSummary(w: Workout): WorkoutSummary {
  let totalSets = 0;
  let totalVolume = 0;
  for (const ex of w.exercises) {
    for (const set of ex.sets) {
      if (set.isCompleted) {
        totalSets++;
        totalVolume += (set.weight ?? 0) * (set.reps ?? 0);
      }
    }
  }
  return {
    id: w.id,
    templateId: w.templateId,
    name: w.name,
    startedAt: w.startedAt,
    completedAt: w.completedAt,
    exerciseCount: w.exercises.length,
    totalSets,
    totalVolume,
  };
}

function isNotFound(err: unknown): boolean {
  return (
    typeof err === "object" &&
    err !== null &&
    "code" in err &&
    (err as { code: number }).code === 404
  );
}
