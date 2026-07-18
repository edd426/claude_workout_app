export interface SyncPullRequest {
  lastSyncTimestamp?: string | null;
  collections: string[];
}

export interface SyncPullResponse {
  workouts: Record<string, unknown>[];
  templates: Record<string, unknown>[];
  chat: Record<string, unknown>[];
  insights: Record<string, unknown>[];
  preferences: Record<string, unknown>[];
  serverTimestamp: string;
}

export interface SyncPushRequest {
  workouts?: Record<string, unknown>[];
  templates?: Record<string, unknown>[];
  chat?: Record<string, unknown>[];
  insights?: Record<string, unknown>[];
  preferences?: Record<string, unknown>[];
}

export type SyncPushRecordStatus = "accepted" | "conflict" | "error";

export interface SyncPushRecordResult {
  id: string;
  collection: string;
  status: SyncPushRecordStatus;
}

export interface SyncPushResponse {
  accepted: number;
  conflicts: number;
  serverTimestamp: string;
  // Per-record outcome for every submitted record. `accepted`/`conflicts` remain
  // for backward compatibility; older clients ignore this added field.
  results: SyncPushRecordResult[];
}

export interface SasRequest {
  path: string;
  mode: "upload" | "download";
}

export interface SasResponse {
  sasUrl: string;
  expiresAt: string;
}

export interface ChatRequest {
  messages: Record<string, unknown>[];
  system?: string | Record<string, unknown>[];
  model?: string;
  max_tokens?: number;
  tools?: Record<string, unknown>[];
  stream?: boolean;
  thinking_budget?: number;
}

export interface InsightsRequest {
  recentWorkoutSummary: string;
  lastInsightDate?: string;
}

export interface Insight {
  content: string;
  type: "suggestion" | "warning" | "encouragement";
}

export interface InsightsResponse {
  insights: Insight[];
}

export interface HealthResponse {
  status: "healthy";
  timestamp: string;
  version: string;
}

// ─── Read API domain types (issue #79) ──────────────────────────────────────
// Cosmos document shapes + derived read-model types for the read-only
// endpoints backing the MCP server (templates, workouts, history, stats,
// calendar). Field names mirror the iOS sync DTOs.

export interface WorkoutTemplate {
  id: string;
  name: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
  lastPerformedAt?: string;
  timesPerformed: number;
  exercises: TemplateExercise[];
  lastModified?: string;
  syncStatus?: string;
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
  lastModified?: string;
  syncStatus?: string;
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

export interface PersonalRecord {
  exerciseId: string;
  exerciseName: string;
  type: "heaviest_weight" | "most_reps" | "highest_volume";
  value: number;
  date: string;
}

export interface Stats {
  totalWorkouts: number;
  totalSets: number;
  totalVolume: number;
  workoutsPerWeek: number;
  personalRecords: PersonalRecord[];
  muscleGroupDistribution: Record<string, number>;
}

export interface CalendarEntry {
  date: string;
  workoutCount: number;
  totalSets: number;
  totalVolume: number;
}
