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

// ─── Snapshot sync (issue #78, wire contract v2) ─────────────────────────────
// The phone is authoritative; Azure is a read-mostly mirror. A push is always
// the complete state of each collection — full-state replace, not deltas.

export const SNAPSHOT_SCHEMA_VERSION = 2;

export interface SnapshotCollections {
  workouts: Record<string, unknown>[];
  templates: Record<string, unknown>[];
  customExercises: Record<string, unknown>[];
  bodyWeightEntries: Record<string, unknown>[];
}

export interface SnapshotPushRequest {
  schemaVersion: number;
  snapshot: SnapshotCollections;
}

export interface SnapshotContainerCounts {
  upserted: number;
  deleted: number;
}

export interface SnapshotCounts {
  workouts: SnapshotContainerCounts;
  templates: SnapshotContainerCounts;
  customExercises: SnapshotContainerCounts;
  bodyWeightEntries: SnapshotContainerCounts;
}

export interface SnapshotPushResponse {
  revision: number;
  serverTime: string;
  counts: SnapshotCounts;
}

export interface SnapshotReadResponse {
  revision: number;
  serverTime: string;
  snapshot: SnapshotCollections;
}

/**
 * Revision metadata, persisted as the single doc id "snapshot" in the
 * `syncMeta` container. `revision` counts successful pushes (monotonically
 * increasing, server-assigned); `serverTime` is when the last successful
 * push was applied.
 */
export interface SyncMetaDoc {
  id: string;
  revision: number;
  serverTime: string;
}

// ─── MCP write inbox (issue #88) ────────────────────────────────────────────
// Durable operations fetched and applied by the phone. This collection is
// deliberately separate from snapshot reconciliation.

export type InboxOperationType =
  | "createTemplate"
  | "updateTemplate"
  | "deleteTemplate"
  | "createCustomExercise";

export type InboxOperationStatus =
  | "pending"
  | "awaitingApproval"
  | "applied"
  | "rejected"
  | "failed";

export interface InboxTemplateExercisePayload {
  externalId: string;
  order: number;
  defaultSets: number;
  defaultReps: number;
  defaultWeight?: number;
  defaultRestSeconds?: number;
  notes?: string;
}

export interface CreateTemplatePayload {
  name: string;
  notes?: string;
  exercises: InboxTemplateExercisePayload[];
}

export interface UpdateTemplatePayload {
  id: string;
  name?: string;
  notes?: string;
  exercises?: InboxTemplateExercisePayload[];
}

export interface DeleteTemplatePayload {
  id: string;
  name: string;
}

export interface CreateCustomExercisePayload {
  name: string;
  equipment?: string;
  primaryMuscles?: string[];
  secondaryMuscles?: string[];
  instructions?: string[];
  notes?: string;
}

export type InboxOperationPayload =
  | CreateTemplatePayload
  | UpdateTemplatePayload
  | DeleteTemplatePayload
  | CreateCustomExercisePayload;

export interface InboxOperation {
  id: string;
  createdAt: string;
  op: InboxOperationType;
  payload: InboxOperationPayload;
  requiresApproval: boolean;
  status: InboxOperationStatus;
  appliedAt?: string;
  error?: string;
}

export type InboxEnqueueRequest =
  | { op: "createTemplate"; payload: CreateTemplatePayload }
  | { op: "updateTemplate"; payload: UpdateTemplatePayload }
  | { op: "deleteTemplate"; payload: DeleteTemplatePayload }
  | { op: "createCustomExercise"; payload: CreateCustomExercisePayload };

export type InboxEnqueueResponse = InboxOperation;

export interface InboxListResponse {
  operations: InboxOperation[];
}

export type InboxAckStatus = Exclude<InboxOperationStatus, "pending">;

export interface InboxAckResult {
  id: string;
  status: InboxAckStatus;
  error?: string;
}

export interface InboxAckRequest {
  results: InboxAckResult[];
}

export interface InboxAckCounts {
  updated: number;
  unchanged: number;
  notFound: number;
  /** Illegal transitions, forced to `failed` so they are never re-served. */
  invalid: number;
}

export interface InboxAckResponse {
  counts: InboxAckCounts;
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
