/**
 * Photos attached to an exercise by its stable externalId (issue #170):
 * blob `exercises/ext/{externalId}.jpg`.
 *
 * The externalId becomes a blob path segment, so its character set is
 * allow-listed exactly rather than deny-listed:
 *
 *   catalog  [A-Za-z0-9][A-Za-z0-9_-]{0,127}       e.g. Barbell_Bench_Press_-_Medium_Grip
 *   custom   custom:{slug}:{lowercase uuid}         slug = [a-z0-9]+(-[a-z0-9]+)*, ≤ 64
 *
 * Neither form admits "/", ".", "%", "\", whitespace or any non-ASCII
 * character, so no id can traverse, nest, change the extension, or smuggle an
 * encoded separator. Custom ids are minted by the Function with randomUUID(),
 * which is always lower-case. The MCP server (infra/mcp) and the phone
 * (InboxApplier.setExercisePhoto) check the same shape.
 */

import { MAX_CUSTOM_EXERCISE_SLUG_LENGTH } from "./customExerciseIdentity";

const CATALOG_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const CUSTOM_ID =
  /^custom:([a-z0-9]+(?:-[a-z0-9]+)*):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const PREFIX = "exercises/ext/";
const SUFFIX = ".jpg";

export function isPhotoExternalId(externalId: string): boolean {
  if (CATALOG_ID.test(externalId)) return true;
  const custom = CUSTOM_ID.exec(externalId);
  return custom !== null && custom[1].length <= MAX_CUSTOM_EXERCISE_SLUG_LENGTH;
}

/** The blob path for an externalId's photo. Callers validate the id first. */
export function exercisePhotoPath(externalId: string): string {
  return `${PREFIX}${externalId}${SUFFIX}`;
}

export function isExercisePhotoPath(path: string): boolean {
  if (!path.startsWith(PREFIX) || !path.endsWith(SUFFIX)) return false;
  return isPhotoExternalId(path.slice(PREFIX.length, path.length - SUFFIX.length));
}
