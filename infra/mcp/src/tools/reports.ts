/**
 * Exercise-report tools (issue #135).
 *
 * `list_exercise_reports` reads the complaint backlog the phone filed;
 * `resolve_exercise_report` closes one out through the durable inbox. Both go
 * through the Functions API — the mirror is a projection of the phone, so a
 * direct write would be erased by the next snapshot push.
 */

import { apiGet, apiPost } from "../shared/http.js";

export type ExerciseReportStatus = "open" | "acknowledged" | "resolved";

export interface ExerciseReport {
  id: string;
  createdAt: string;
  category: string;
  detail: string;
  exerciseExternalId?: string | null;
  exerciseName?: string | null;
  suggestedReplacement?: string | null;
  workoutId?: string | null;
  workoutExerciseId?: string | null;
  templateId?: string | null;
  contextSummary?: string | null;
  status: string;
  resolution?: string | null;
  appVersion?: string | null;
  iosVersion?: string | null;
  photoURL?: string | null;
  lastModified: string;
}

export interface InboxOperation {
  id: string;
  createdAt: string;
  op: string;
  payload: Record<string, unknown>;
  requiresApproval: boolean;
  status: string;
}

const LIST_STATUSES: readonly string[] = [
  "open",
  "acknowledged",
  "resolved",
  "all",
];

const CATEGORIES: readonly string[] = [
  "bug",
  "swapRequest",
  "wrongExercise",
  "dataError",
  "formOrSetup",
  "other",
];

const RESOLVE_STATUSES: readonly string[] = ["resolved", "acknowledged"];

export async function listExerciseReports(
  options: {
    status?: string;
    category?: string;
    exerciseExternalId?: string;
    limit?: number;
  } = {}
): Promise<ExerciseReport[]> {
  if (options.status !== undefined && !LIST_STATUSES.includes(options.status)) {
    throw new Error(
      `Unknown report status: ${options.status}. ` +
        `Expected one of ${LIST_STATUSES.join(", ")}.`
    );
  }
  if (
    options.category !== undefined &&
    !CATEGORIES.includes(options.category)
  ) {
    throw new Error(
      `Unknown report category: ${options.category}. ` +
        `Expected one of ${CATEGORIES.join(", ")}.`
    );
  }

  const { reports } = await apiGet<{ reports: ExerciseReport[] }>("reports", {
    status: options.status,
    category: options.category,
    exerciseExternalId: options.exerciseExternalId,
    limit: options.limit,
  });
  return reports;
}

/**
 * Enqueues the close-out. The report is not actually closed until the phone
 * next syncs and drains the inbox — this returns the queued operation, not a
 * finished write, and saying otherwise would be a lie about a durable queue.
 */
export async function resolveExerciseReport(
  args: unknown
): Promise<InboxOperation> {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    throw new Error("Arguments must be an object");
  }
  const input = args as Record<string, unknown>;

  const id = input["id"];
  if (typeof id !== "string" || id.trim().length === 0) {
    throw new Error("id must be a non-empty string");
  }
  const status = input["status"];
  if (status !== undefined && !RESOLVE_STATUSES.includes(status as string)) {
    throw new Error(
      `status must be one of ${RESOLVE_STATUSES.join(", ")} — ` +
        "a report cannot be reopened from here"
    );
  }
  const resolution = input["resolution"];
  if (resolution !== undefined && typeof resolution !== "string") {
    throw new Error("resolution must be a string");
  }

  return apiPost<InboxOperation>("inbox", {
    op: "resolveExerciseReport",
    payload: { id, status, resolution },
  });
}
