export interface Exercise {
  id: string;
  name: string;
  force?: string;
  level?: string;
  mechanic?: string;
  equipment?: string;
  instructions?: string[];
  imageURL?: string;
  photoURL?: string;
  notes?: string;
  tags?: ExerciseTag[];
  isCustom: boolean;
  primaryMuscles?: string[];
  secondaryMuscles?: string[];
}

export interface ExerciseTag {
  id: string;
  category: string;
  value: string;
}

export interface WorkoutTemplate {
  id: string;
  name: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
  lastPerformedAt?: string;
  timesPerformed: number;
  exercises: TemplateExercise[];
}

export interface TemplateExercise {
  id: string;
  order: number;
  exerciseId: string;
  exerciseName: string;
  defaultSets: number;
  defaultReps: number;
  defaultWeight?: number;
  defaultRestSeconds: number;
  notes?: string;
}

export interface Workout {
  id: string;
  templateId?: string;
  name: string;
  startedAt: string;
  completedAt?: string;
  notes?: string;
  exercises: WorkoutExercise[];
}

export interface WorkoutExercise {
  id: string;
  order: number;
  exerciseId: string;
  exerciseName: string;
  notes?: string;
  restSeconds: number;
  sets: WorkoutSet[];
}

export interface WorkoutSet {
  id: string;
  order: number;
  weight?: number;
  weightUnit: "kg" | "lbs";
  reps?: number;
  isCompleted: boolean;
  completedAt?: string;
  notes?: string;
}

export interface WorkoutSummary {
  id: string;
  templateId?: string;
  name: string;
  startedAt: string;
  completedAt?: string;
  exerciseCount: number;
  totalSets: number;
  totalVolume: number;
}

export interface ExerciseHistoryEntry {
  workoutId: string;
  workoutName: string;
  date: string;
  sets: WorkoutSet[];
}

export interface Stats {
  totalWorkouts: number;
  totalSets: number;
  totalVolume: number;
  workoutsPerWeek: number;
  personalRecords: PersonalRecord[];
  muscleGroupDistribution: Record<string, number>;
}

export interface PersonalRecord {
  exerciseId: string;
  exerciseName: string;
  type: "heaviest_weight" | "most_reps" | "highest_volume";
  value: number;
  date: string;
}

export interface CalendarEntry {
  date: string;
  workoutCount: number;
  totalSets: number;
  totalVolume: number;
}
