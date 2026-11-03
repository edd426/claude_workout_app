/**
 * Photos attached to an exercise by its stable externalId (issue #170):
 * blob `exercises/ext/{externalId}.jpg`.
 *
 * Mirrors infra/functions/src/shared/exercisePhotoPath.ts, which the SAS
 * endpoint and the inbox enqueue enforce; this copy lets the tool refuse a
 * bad id before any request. The id becomes a blob path segment, so its
 * character set is allow-listed exactly:
 *
 *   catalog  [A-Za-z0-9][A-Za-z0-9_-]{0,127}       e.g. Barbell_Bench_Press_-_Medium_Grip
 *   custom   custom:{slug}:{lowercase uuid}         slug = [a-z0-9]+(-[a-z0-9]+)*, ≤ 64
 *
 * No "/", ".", "%", "\", whitespace or non-ASCII character can appear.
 */

import { MAX_CUSTOM_EXERCISE_SLUG_LENGTH } from "./customExerciseIdentity.js";

const CATALOG_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const CUSTOM_ID =
  /^custom:([a-z0-9]+(?:-[a-z0-9]+)*):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function isPhotoExternalId(externalId: string): boolean {
  if (CATALOG_ID.test(externalId)) return true;
  const custom = CUSTOM_ID.exec(externalId);
  return custom !== null && custom[1].length <= MAX_CUSTOM_EXERCISE_SLUG_LENGTH;
}

/** The blob path for an externalId's photo. Callers validate the id first. */
export function exercisePhotoPath(externalId: string): string {
  return `exercises/ext/${externalId}.jpg`;
}
