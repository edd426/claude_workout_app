/**
 * Pure aggregation helpers for the read-only API endpoints (issue #79).
 * Ported from the former MCP-server Cosmos tools so the Functions API is the
 * single data-access layer; the MCP server is now a thin HTTP client.
 */

import {
  Workout,
  WorkoutSummary,
  ExerciseHistoryEntry,
  Stats,
  PersonalRecord,
  CalendarEntry,
} from "./types";

export function toSummary(workout: Workout): WorkoutSummary {
  let totalSets = 0;
  let totalVolume = 0;
  for (const ex of workout.exercises ?? []) {
    for (const set of ex.sets ?? []) {
      if (set.isCompleted) {
        totalSets++;
        totalVolume += (set.weight ?? 0) * (set.reps ?? 0);
      }
    }
  }
  return {
    id: workout.id,
    templateId: workout.templateId,
    name: workout.name,
    startedAt: workout.startedAt,
    completedAt: workout.completedAt,
    exerciseCount: (workout.exercises ?? []).length,
    totalSets,
    totalVolume,
  };
}

export function extractExerciseHistory(
  workouts: Workout[],
  exerciseId: string,
  limit: number
): ExerciseHistoryEntry[] {
  const entries: ExerciseHistoryEntry[] = [];
  for (const workout of workouts) {
    for (const ex of workout.exercises ?? []) {
      if (ex.exerciseId === exerciseId) {
        entries.push({
          workoutId: workout.id,
          workoutName: workout.name,
          date: workout.startedAt,
          sets: ex.sets ?? [],
        });
      }
    }
  }
  return entries.slice(0, limit);
}

export function computeStats(workouts: Workout[]): Stats {
  let totalSets = 0;
  let totalVolume = 0;
  const personalRecords: PersonalRecord[] = [];
  const muscleDistribution: Record<string, number> = {};
  const prMap = new Map<
    string,
    { weight: number; reps: number; volume: number; date: string; name: string }
  >();

  for (const workout of workouts) {
    for (const ex of workout.exercises ?? []) {
      for (const set of ex.sets ?? []) {
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

  // Workouts per week — assumes workouts are sorted newest-first.
  let workoutsPerWeek = 0;
  if (workouts.length >= 2) {
    const first = new Date(workouts[workouts.length - 1].startedAt);
    const last = new Date(workouts[0].startedAt);
    const weeks = Math.max(
      1,
      (last.getTime() - first.getTime()) / (7 * 24 * 60 * 60 * 1000)
    );
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

export function buildCalendar(workouts: Workout[]): CalendarEntry[] {
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
    for (const ex of workout.exercises ?? []) {
      for (const set of ex.sets ?? []) {
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
