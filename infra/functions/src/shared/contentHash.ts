/**
 * Content hashing for snapshot reconciliation (scaling for the Jefit history,
 * #166). Every doc the snapshot push stores carries `_contentHash`: the sha256
 * of its canonical JSON, with Cosmos system fields and the hash itself left
 * out. A push compares hashes and writes only new or changed docs.
 *
 * Canonical JSON: object keys sorted (recursively), arrays in order, no
 * whitespace. The phone's JSONEncoder does not promise key order, so sorting
 * keeps an unchanged record from looking changed; array order is meaningful
 * (the phone sorts nested exercises and sets by `order` before encoding).
 */

import { createHash } from "node:crypto";

/** Server-owned: written on every stored doc, never served to a reader. */
export const CONTENT_HASH_FIELD = "_contentHash";

/** Cosmos system properties, plus the hash: never part of the content. */
export const SERVER_FIELDS: readonly string[] = [
  "_rid",
  "_self",
  "_etag",
  "_attachments",
  "_ts",
  CONTENT_HASH_FIELD,
];

export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    const object = value as Record<string, unknown>;
    const members = Object.keys(object)
      .filter((key) => object[key] !== undefined)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`);
    return `{${members.join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

/** The client's content: the doc without any server-owned top-level field. */
export function clientContent(doc: Record<string, unknown>): Record<string, unknown> {
  const content: Record<string, unknown> = { ...doc };
  for (const field of SERVER_FIELDS) delete content[field];
  return content;
}

/** sha256 (hex) of the canonical JSON of the doc's client content. */
export function contentHash(doc: Record<string, unknown>): string {
  return createHash("sha256").update(canonicalJson(clientContent(doc))).digest("hex");
}
