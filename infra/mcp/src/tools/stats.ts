import { getContainer } from "../shared/cosmos.js";
import type {
  Workout,
  Stats,
  PersonalRecord,
  CalendarEntry,
} from "../shared/types.js";

export async function getStats(options?: {
  startDate?: string;
  endDate?: string;
}): Promise<Stats> {
  const container = getContainer("workouts");
  const conditions: string[] = [];
  const parameters: { name: string; value: string }[] = [];

  if (options?.startDate) {
    conditions.push("c.startedAt >= @startDate");
    parameters.push({ name: "@startDate", value: options.startDate });
  }
  if (options?.endDate) {
    conditions.push("c.startedAt <= @endDate");
    parameters.push({ name: "@endDate", value: options.endDate });
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  const query = `SELECT * FROM c ${where} ORDER BY c.startedAt DESC`;

  const { resources } = await container.items
    .query({ query, parameters })
    .fetchAll();

  const workouts = resources as Workout[];
  return computeStats(workouts);
}

function computeStats(workouts: Workout[]): Stats {
  let totalSets = 0;
  let totalVolume = 0;
  const personalRecords: PersonalRecord[] = [];
  const muscleDistribution: Record<string, number> = {};
  const prMap = new Map<string, { weight: number; reps: number; volume: number; date: string; name: string }>();

  for (const workout of workouts) {
    for (const ex of workout.exercises) {
      for (const set of ex.sets) {
        if (!set.isCompleted) continue;
        totalSets++;
        const volume = (set.weight ?? 0) * (set.reps ?? 0);
        totalVolume += volume;

        const existing = prMap.get(ex.exerciseId);
        if (!existing) {
          prMap.set(ex.exerciseId, {
            weight: set.weight ?? 0,
            reps: set.reps ?? 0,
            volume,
            date: workout.startedAt,
            name: ex.exerciseName,
          });
        } else {
          if ((set.weight ?? 0) > existing.weight) {
            existing.weight = set.weight ?? 0;
            existing.date = workout.startedAt;
          }
          if ((set.reps ?? 0) > existing.reps) {
            existing.reps = set.reps ?? 0;
          }
          if (volume > existing.volume) {
            existing.volume = volume;
          }
        }
      }
    }
  }

  for (const [exerciseId, pr] of prMap) {
    if (pr.weight > 0) {
      personalRecords.push({
        exerciseId,
        exerciseName: pr.name,
        type: "heaviest_weight",
        value: pr.weight,
        date: pr.date,
      });
    }
  }

  // Calculate workouts per week
  let workoutsPerWeek = 0;
  if (workouts.length >= 2) {
    const first = new Date(workouts[workouts.length - 1].startedAt);
    const last = new Date(workouts[0].startedAt);
    const weeks = Math.max(1, (last.getTime() - first.getTime()) / (7 * 24 * 60 * 60 * 1000));
    workoutsPerWeek = Math.round((workouts.length / weeks) * 10) / 10;
  } else if (workouts.length === 1) {
    workoutsPerWeek = 1;
  }

  return {
    totalWorkouts: workouts.length,
    totalSets,
    totalVolume,
    workoutsPerWeek,
    personalRecords,
    muscleGroupDistribution: muscleDistribution,
  };
}

export async function getCalendar(
  startDate: string,
  endDate: string,
): Promise<CalendarEntry[]> {
  const container = getContainer("workouts");
  const query = `SELECT * FROM c WHERE c.startedAt >= @startDate AND c.startedAt <= @endDate ORDER BY c.startedAt`;
  const { resources } = await container.items
    .query({
      query,
      parameters: [
        { name: "@startDate", value: startDate },
        { name: "@endDate", value: endDate },
      ],
    })
    .fetchAll();

  const workouts = resources as Workout[];
  const dayMap = new Map<string, CalendarEntry>();

  for (const workout of workouts) {
    const date = workout.startedAt.substring(0, 10); // YYYY-MM-DD
    const existing = dayMap.get(date) ?? {
      date,
      workoutCount: 0,
      totalSets: 0,
      totalVolume: 0,
    };
    existing.workoutCount++;
    for (const ex of workout.exercises) {
      for (const set of ex.sets) {
        if (set.isCompleted) {
          existing.totalSets++;
          existing.totalVolume += (set.weight ?? 0) * (set.reps ?? 0);
        }
      }
    }
    dayMap.set(date, existing);
  }

  return Array.from(dayMap.values()).sort((a, b) => a.date.localeCompare(b.date));
}
