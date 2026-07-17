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
