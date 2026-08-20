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

/// Every status the write path will set, reopening included (#146).
///
/// `open` was refused here until a real case forced the question: #136 was
/// acknowledged, its fix shipped, and the fix turned out to be inert. With no
/// route back, a genuine complaint had left the backlog permanently. Reopening
/// is also the safe direction — it surfaces a complaint rather than hiding
/// one, so it needs no approval gate.
const RESOLVE_STATUSES: readonly string[] = ["resolved", "acknowledged", "open"];

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
 * Sets a report's status through the durable inbox. The report is not actually
 * changed until the phone next syncs and drains the inbox — this returns the
 * queued operation(s), not a finished write, and saying otherwise would be a
 * lie about a durable queue.
 *
 * Takes either `id` (returns one operation) or `ids` (returns an array, one
 * per report). Closing out a gym session means answering several reports at
 * once, and one call each is several round trips plus several chances to lose
 * track of which are done.
 *
 * Every id is validated before any of them is enqueued: a batch that half
 * applies is worse than one that is refused.
 */
export async function resolveExerciseReport(
  args: unknown
): Promise<InboxOperation | InboxOperation[]> {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    throw new Error("Arguments must be an object");
  }
  const input = args as Record<string, unknown>;

  const rawId = input["id"];
  const rawIds = input["ids"];
  if (rawId !== undefined && rawIds !== undefined) {
    throw new Error("Pass either id or ids, not both");
  }

  const isBatch = rawIds !== undefined;
  if (isBatch && !Array.isArray(rawIds)) {
    throw new Error("ids must be an array of report UUIDs");
  }
  const ids = isBatch ? (rawIds as unknown[]) : [rawId];
  if (ids.length === 0) {
    throw new Error("ids must contain at least one report UUID");
  }
  for (const candidate of ids) {
    if (typeof candidate !== "string" || candidate.trim().length === 0) {
      throw new Error("id must be a non-empty string");
    }
  }

  const status = input["status"];
  if (status !== undefined && !RESOLVE_STATUSES.includes(status as string)) {
    throw new Error(
      `status must be one of ${RESOLVE_STATUSES.join(", ")}`
    );
  }
  const resolution = input["resolution"];
  if (resolution !== undefined && typeof resolution !== "string") {
    throw new Error("resolution must be a string");
  }

  const operations: InboxOperation[] = [];
  for (const id of ids as string[]) {
    operations.push(
      await apiPost<InboxOperation>("inbox", {
        op: "resolveExerciseReport",
        payload: { id, status, resolution },
      })
    );
  }
  return isBatch ? operations : operations[0];
}
