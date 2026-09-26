/**
 * Exercise-report tools (issue #135).
 *
 * `list_exercise_reports` reads the complaint backlog the phone filed;
 * `resolve_exercise_report` closes one out through the durable inbox. Both go
 * through the Functions API — the mirror is a projection of the phone, so a
 * direct write would be erased by the next snapshot push.
 *
 * `get_report_photo` (issue #141) shows the photo attached to a report.
 */

import { ApiError, apiGet, apiPost } from "../shared/http.js";

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

// ─── Report photos (issue #141) ──────────────────────────────────────────────
// The phone uploads a report's photo to blob `reports/{reportId}.jpg` and only
// after that upload succeeds sets `photoURL` to that blob *path* (not a URL),
// which reaches the mirror through snapshot sync. So a non-null photoURL means
// the blob should exist, and a null one means no photo — or one still waiting
// for connectivity to upload.

const UUID =
  "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}";

/**
 * The only shape a report's photoURL may take. Mirror data is checked here
 * before it goes anywhere near a SAS request; the Functions API validates the
 * path as well, but this server does not rely on that.
 */
const REPORT_PHOTO_PATH = new RegExp(`^reports/(${UUID})\\.jpg$`);

/**
 * The largest photo returned, in raw bytes. Chosen so the base64 payload
 * stays within 5 MB, the Claude API's per-image limit. The phone sends a
 * 1024px JPEG, so real photos are ~100–300 KB; anything near this cap is not
 * a photo the app uploaded normally.
 */
export const MAX_REPORT_PHOTO_BYTES = 3_750_000;

/** How many reports a lookup by id scans — the /api/reports limit cap. */
const REPORT_LOOKUP_LIMIT = 500;

const BLOB_DOWNLOAD_TIMEOUT_MS = 30_000;

export interface ReportPhotoImage {
  /** Base64-encoded JPEG. */
  data: string;
  mimeType: "image/jpeg";
  bytes: number;
  path: string;
}

export interface ReportPhoto {
  report: ExerciseReport;
  /** Plain-text description of the report, so the model knows what it sees. */
  caption: string;
  /** Null when no photo is attached, or it has not uploaded yet. */
  image: ReportPhotoImage | null;
}

/**
 * Fetches the photo attached to a report. Returns `image: null` (not an
 * error) when the report has no photoURL — the photo may simply not have
 * uploaded yet. Throws for an unknown report, a malformed photoURL, a blob
 * missing from storage, an oversize blob, or one that is not a JPEG.
 */
export async function getReportPhoto(id: string): Promise<ReportPhoto> {
  const report = await findReport(id);

  if (report.photoURL === null || report.photoURL === undefined) {
    return {
      report,
      caption:
        `${describeReport(report)}\n\n` +
        "No photo is attached to this report, or it has not uploaded yet. " +
        "The phone uploads a report's photo on its next sync with " +
        "connectivity (the gym is often offline) and only then sets " +
        "photoURL, so check again after the phone has synced.",
      image: null,
    };
  }

  const path = validatedPhotoPath(report);
  const sasUrl = await requestDownloadUrl(path);
  const bytes = await downloadPhoto(sasUrl, report, path);

  return {
    report,
    caption: `${describeReport(report)}\nPhoto: ${path} (${formatSize(bytes.length)})`,
    image: {
      data: Buffer.from(bytes).toString("base64"),
      mimeType: "image/jpeg",
      bytes: bytes.length,
      path,
    },
  };
}

async function findReport(id: string): Promise<ExerciseReport> {
  // The mirror holds Swift's upper-case uuidString; callers may not.
  const wanted = id.trim().toLowerCase();
  const reports = await listExerciseReports({
    status: "all",
    limit: REPORT_LOOKUP_LIMIT,
  });
  const report = reports.find(
    (candidate) =>
      typeof candidate.id === "string" && candidate.id.toLowerCase() === wanted
  );
  if (!report) {
    const scope =
      reports.length >= REPORT_LOOKUP_LIMIT
        ? ` (searched the ${REPORT_LOOKUP_LIMIT} most recent reports)`
        : "";
    throw new Error(`Report not found: ${id}${scope}`);
  }
  return report;
}

function validatedPhotoPath(report: ExerciseReport): string {
  const photoURL = report.photoURL;
  const match =
    typeof photoURL === "string" ? REPORT_PHOTO_PATH.exec(photoURL) : null;
  if (!match) {
    throw new Error(
      `Report ${report.id} has a photoURL that is not a report photo path ` +
        `(expected "reports/{reportId}.jpg"): ` +
        `${JSON.stringify(photoURL).slice(0, 200)}. Refusing to request it.`
    );
  }
  if (match[1].toLowerCase() !== report.id.toLowerCase()) {
    throw new Error(
      `Report ${report.id} has a photoURL naming a different report's ` +
        `photo (${photoURL}). Refusing to show it as this report's photo.`
    );
  }
  return match[0];
}

async function requestDownloadUrl(path: string): Promise<string> {
  let sasUrl: unknown;
  try {
    ({ sasUrl } = await apiGet<{ sasUrl?: unknown }>("images/sas", {
      path,
      mode: "download",
    }));
  } catch (err) {
    // The path was validated above, so a 400 here almost certainly means the
    // deployed Functions app still has the pre-#141 exercises-only lock.
    if (err instanceof ApiError && err.status === 400) {
      throw new Error(
        `${err.message}. The Functions API refused a reports/ photo path; ` +
          "it accepts them only from #141 on, so the deployed Functions app " +
          "is likely older than that — redeploy it."
      );
    }
    throw err;
  }
  if (typeof sasUrl !== "string" || sasUrl.length === 0) {
    throw new Error("Functions API returned no sasUrl for the report photo");
  }
  return sasUrl;
}

/**
 * Downloads the blob. The SAS URL is a bearer credential, so errors name the
 * blob path and never the URL, and the Functions API key is never sent.
 */
async function downloadPhoto(
  sasUrl: string,
  report: ExerciseReport,
  path: string
): Promise<Uint8Array> {
  let response: Response;
  try {
    response = await fetch(sasUrl, {
      signal: AbortSignal.timeout(BLOB_DOWNLOAD_TIMEOUT_MS),
    });
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot download ${path} from blob storage: ${detail}`);
  }

  if (response.status === 404) {
    await discardBody(response);
    throw new Error(
      `Report ${report.id} points at photo ${path}, but that photo is not in ` +
        "blob storage. The phone sets photoURL only after a successful " +
        "upload, so the blob has since been removed or the upload did not " +
        "really land."
    );
  }
  if (!response.ok) {
    await discardBody(response);
    throw new Error(
      `Blob storage returned ${response.status} when downloading ${path}`
    );
  }

  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_REPORT_PHOTO_BYTES) {
    await discardBody(response);
    throw tooLarge(path, declared);
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > MAX_REPORT_PHOTO_BYTES) {
    throw tooLarge(path, bytes.length);
  }
  if (!isJpeg(bytes)) {
    throw new Error(
      `Report photo ${path} is not a JPEG (${formatSize(bytes.length)}); ` +
        "refusing to return it labelled image/jpeg."
    );
  }
  return bytes;
}

async function discardBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // Nothing useful to do; the error being thrown is what matters.
  }
}

function tooLarge(path: string, bytes: number): Error {
  return new Error(
    `Report photo ${path} is too large to return (${formatSize(bytes)}; ` +
      `the limit is ${formatSize(MAX_REPORT_PHOTO_BYTES)}). The phone uploads ` +
      "~100–300 KB JPEGs, so this is not a photo it uploaded normally."
  );
}

/** JPEG files start with the SOI marker FF D8 followed by another FF. */
function isJpeg(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  );
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} bytes`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function describeReport(report: ExerciseReport): string {
  const subject = report.exerciseName ?? "no exercise attached";
  const lines = [
    `Report ${report.id} — ${report.category}: ${subject}`,
    `Status: ${report.status} · filed ${report.createdAt}`,
    `Detail: ${report.detail}`,
  ];
  if (report.suggestedReplacement) {
    lines.push(`Suggested replacement: ${report.suggestedReplacement}`);
  }
  return lines.join("\n");
}
