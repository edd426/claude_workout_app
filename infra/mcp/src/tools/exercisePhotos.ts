/**
 * attach_exercise_photo (issue #170): put a photo of the real machine on an
 * exercise card, from Claude.
 *
 * Every check that needs no network runs first, and each step is refused
 * before the next on failure:
 *   1. externalId has the exact photo-path grammar (exercisePhotoPath.ts)
 *   2. imageBase64 decodes to a JPEG of at most 3.75 MB
 *   3. the exercise exists: bundled catalog, or a synced/queued custom one
 *   4. a WRITE SAS from GET /api/images/sas for exercises/ext/{externalId}.jpg
 *   5. PUT straight to Blob Storage. The SAS is the only credential sent
 *      there; the Functions API key never is, and errors name the blob path,
 *      never the SAS URL (a bearer credential)
 *   6. enqueue setExercisePhoto { externalId, blobPath }. The Function marks
 *      it requiresApproval, so nothing changes on the phone until it is
 *      approved there (one batch approval covers many photos).
 *
 * Uploading before enqueueing means an op never points at a missing blob. The
 * blob path is deterministic per exercise, so attaching again replaces it.
 *
 * The image comes from exactly one of:
 *   - imageBase64: works on both servers, but the model has to write out the
 *     whole base64 text (~270,000 characters for a 200 KB photo);
 *   - imagePath: an absolute path to a local .jpg/.jpeg, read by this process.
 *     Only the local (stdio) server allows it. The remote claude.ai server runs
 *     on Azure, where a readable path would be a file on the Function host, so
 *     it refuses before touching the filesystem.
 */

import { constants } from "node:fs";
import { open, realpath, stat } from "node:fs/promises";
import { extname, isAbsolute } from "node:path";

import { ApiError, apiGet, apiPost } from "../shared/http.js";
import { exercisePhotoPath, isPhotoExternalId } from "../shared/exercisePhotoPath.js";
import { discardBody, formatSize, isJpeg, MAX_PHOTO_BYTES } from "../shared/jpeg.js";
import { resolveExerciseByExternalId } from "./catalog.js";
import { unknownExternalIdError } from "./writes.js";

export const MAX_EXERCISE_PHOTO_BYTES = MAX_PHOTO_BYTES;

/** Longest base64 text that can decode to MAX_EXERCISE_PHOTO_BYTES. */
const MAX_BASE64_LENGTH = Math.ceil(MAX_EXERCISE_PHOTO_BYTES / 3) * 4;

const BLOB_UPLOAD_TIMEOUT_MS = 60_000;

const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
const JPEG_DATA_URL = /^data:image\/jpe?g;base64,/i;
const JPEG_EXTENSIONS = new Set([".jpg", ".jpeg"]);

export const LOCAL_FILES_ONLY_MESSAGE =
  "imagePath is only available on the local server; send imageBase64";

export interface AttachExercisePhotoOptions {
  /** True only on the local (stdio) server: lets imagePath read a local file. */
  allowLocalFiles?: boolean;
}

export interface InboxOperation {
  id: string;
  createdAt?: string;
  op?: string;
  payload?: Record<string, unknown>;
  requiresApproval?: boolean;
  status?: string;
}

export interface AttachExercisePhotoResult {
  operation: InboxOperation;
  exercise: { externalId: string; name: string };
  blobPath: string;
  bytes: number;
  note: string;
}

function validatedExternalId(value: unknown): string {
  if (typeof value !== "string" || !isPhotoExternalId(value)) {
    throw new Error(
      `externalId ${JSON.stringify(value)} is not an exercise externalId: ` +
        "expected a catalog id (letters, digits, _ and -, from search_exercises) " +
        "or a custom:{slug}:{uuid} id"
    );
  }
  return value;
}

/** Decodes and checks the image without touching the network. */
function decodedJpeg(value: unknown): Buffer {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error("imageBase64 must be a non-empty base64 string of a JPEG");
  }
  let text = value.trim();
  const dataUrl = JPEG_DATA_URL.exec(text);
  if (dataUrl) {
    text = text.slice(dataUrl[0].length);
  } else if (/^data:/i.test(text)) {
    throw new Error("imageBase64 is a data URL for something other than a JPEG");
  }
  text = text.replace(/\s+/g, "");

  if (text.length > MAX_BASE64_LENGTH) {
    throw tooLarge(Math.floor((text.length * 3) / 4));
  }
  if (!BASE64.test(text) || text.length % 4 === 1) {
    throw new Error("imageBase64 is not valid base64");
  }

  return checkedJpeg(Buffer.from(text, "base64"));
}

/** The same size and JPEG checks for both sources. */
function checkedJpeg(bytes: Buffer): Buffer {
  if (bytes.length > MAX_EXERCISE_PHOTO_BYTES) throw tooLarge(bytes.length);
  if (!isJpeg(bytes)) {
    throw new Error(
      `The image is not a JPEG (${formatSize(bytes.length)}). Exercise photos ` +
        "are stored and shown as JPEG; convert it first."
    );
  }
  return bytes;
}

function hasJpegExtension(path: string): boolean {
  return JPEG_EXTENSIONS.has(extname(path).toLowerCase());
}

function errnoCode(err: unknown): string {
  const code = (err as NodeJS.ErrnoException).code;
  return typeof code === "string" ? code : err instanceof Error ? err.name : "error";
}

/**
 * Reads a local JPEG for imagePath, with fs calls only (no shell). Symlinks
 * are resolved first and every check applies to the real file: a `.jpg` link
 * to some other file is refused. The size is checked before reading and the
 * bytes again after, and the real path is opened with O_NOFOLLOW so it cannot
 * be swapped for a link in between.
 */
async function readLocalJpeg(value: unknown): Promise<Buffer> {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error("imagePath must be an absolute path to a .jpg or .jpeg file");
  }
  if (!isAbsolute(value)) {
    throw new Error(
      `imagePath must be an absolute path (got ${JSON.stringify(value)}; "~" is not expanded)`
    );
  }
  if (!hasJpegExtension(value)) {
    throw new Error(`imagePath must name a .jpg or .jpeg file: ${value}`);
  }

  let real: string;
  try {
    real = await realpath(value);
  } catch (err) {
    throw new Error(`Cannot read imagePath ${value} (${errnoCode(err)})`);
  }
  if (!hasJpegExtension(real)) {
    throw new Error(
      `imagePath ${value} resolves to ${real}, which is not a .jpg or .jpeg file`
    );
  }

  let info;
  try {
    info = await stat(real);
  } catch (err) {
    throw new Error(`Cannot read imagePath ${value} (${errnoCode(err)})`);
  }
  if (!info.isFile()) throw new Error(`imagePath ${value} is not a regular file`);
  if (info.size > MAX_EXERCISE_PHOTO_BYTES) throw tooLarge(info.size);

  let bytes: Buffer;
  try {
    const handle = await open(real, constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const opened = await handle.stat();
      if (!opened.isFile()) throw new Error(`imagePath ${value} is not a regular file`);
      if (opened.size > MAX_EXERCISE_PHOTO_BYTES) throw tooLarge(opened.size);
      bytes = await handle.readFile();
    } finally {
      await handle.close();
    }
  } catch (err) {
    if (err instanceof Error && /^(imagePath|The image)/.test(err.message)) throw err;
    throw new Error(`Cannot read imagePath ${value} (${errnoCode(err)})`);
  }
  return checkedJpeg(bytes);
}

/** Exactly one source; imagePath only where local files are allowed. */
async function imageFrom(
  input: Record<string, unknown>,
  options: AttachExercisePhotoOptions
): Promise<Buffer> {
  const hasBase64 = input["imageBase64"] !== undefined;
  const hasPath = input["imagePath"] !== undefined;
  if (hasBase64 === hasPath) {
    throw new Error(
      "Pass exactly one of imageBase64 or imagePath" +
        (options.allowLocalFiles ? "" : " (imagePath is only available on the local server)")
    );
  }
  if (hasPath) {
    if (options.allowLocalFiles !== true) throw new Error(LOCAL_FILES_ONLY_MESSAGE);
    return readLocalJpeg(input["imagePath"]);
  }
  return decodedJpeg(input["imageBase64"]);
}

function tooLarge(bytes: number): Error {
  return new Error(
    `The image is too large (${formatSize(bytes)}; the limit is ` +
      `${formatSize(MAX_EXERCISE_PHOTO_BYTES)}). The app's own photos are ` +
      "1024px JPEGs of ~100–300 KB; resize it first."
  );
}

async function requestUploadUrl(path: string): Promise<string> {
  let sasUrl: unknown;
  try {
    ({ sasUrl } = await apiGet<{ sasUrl?: unknown }>("images/sas", {
      path,
      mode: "upload",
    }));
  } catch (err) {
    // The path was validated above, so a 400 almost certainly means the
    // deployed Functions app still has the pre-#170 allow-list.
    if (err instanceof ApiError && err.status === 400) {
      throw new Error(
        `${err.message}. The Functions API refused an exercises/ext/ photo ` +
          "path; it accepts them only from #170 on, so the deployed Functions " +
          "app is likely older than that — redeploy it."
      );
    }
    throw err;
  }
  if (typeof sasUrl !== "string" || sasUrl.length === 0) {
    throw new Error("Functions API returned no sasUrl for the exercise photo");
  }

  // Upload only to the blob that was asked for, over HTTPS.
  let url: URL;
  try {
    url = new URL(sasUrl);
  } catch {
    throw new Error("Functions API returned an unusable upload URL");
  }
  if (url.protocol !== "https:" || !decodeURIComponent(url.pathname).endsWith(`/${path}`)) {
    throw new Error(
      `Functions API returned an upload URL for a different blob than ${path}; refusing to upload`
    );
  }
  return sasUrl;
}

async function uploadPhoto(sasUrl: string, path: string, bytes: Buffer): Promise<void> {
  let response: Response;
  try {
    response = await fetch(sasUrl, {
      method: "PUT",
      headers: { "x-ms-blob-type": "BlockBlob", "content-type": "image/jpeg" },
      body: new Uint8Array(bytes),
      signal: AbortSignal.timeout(BLOB_UPLOAD_TIMEOUT_MS),
    });
  } catch (err) {
    // The underlying error can carry the URL, and the URL is a credential.
    const name = err instanceof Error ? err.name : "Error";
    throw new Error(`Cannot upload ${path} to blob storage (${name})`);
  }
  if (!response.ok) {
    await discardBody(response);
    throw new Error(`Blob storage returned ${response.status} when uploading ${path}`);
  }
  await discardBody(response);
}

export async function attachExercisePhoto(
  args: unknown,
  options: AttachExercisePhotoOptions = {}
): Promise<AttachExercisePhotoResult> {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    throw new Error("Arguments must be an object");
  }
  const input = args as Record<string, unknown>;

  const externalId = validatedExternalId(input["externalId"]);
  const bytes = await imageFrom(input, options);

  const exercise = await resolveExerciseByExternalId(externalId);
  if (!exercise) throw unknownExternalIdError(externalId);

  const blobPath = exercisePhotoPath(externalId);
  const sasUrl = await requestUploadUrl(blobPath);
  await uploadPhoto(sasUrl, blobPath, bytes);

  let operation: InboxOperation;
  try {
    operation = await apiPost<InboxOperation>("inbox", {
      op: "setExercisePhoto",
      payload: { externalId, blobPath },
    });
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(
      `The photo was uploaded to ${blobPath} but not queued for the phone: ${detail}. ` +
        (err instanceof ApiError && err.status === 400
          ? "The deployed Functions app likely predates #170 (setExercisePhoto); " +
            "redeploy it, then attach the photo again."
          : "Attach the photo again to queue it.")
    );
  }

  return {
    operation,
    exercise: { externalId, name: exercise.name },
    blobPath,
    bytes: bytes.length,
    note:
      "Uploaded and queued. The photo appears on the exercise card only after " +
      "it is approved on the phone (Home → pending changes), on its next sync. " +
      "Attaching another photo to this exercise replaces this one.",
  };
}
