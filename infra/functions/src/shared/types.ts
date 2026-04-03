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

export interface SyncPushResponse {
  accepted: number;
  conflicts: number;
  serverTimestamp: string;
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
