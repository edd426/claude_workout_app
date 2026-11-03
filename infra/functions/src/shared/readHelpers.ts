/**
 * Shared request-validation and Cosmos point-read helpers for the read-only
 * API endpoints (issue #79). All query inputs are validated and bounded so a
 * huge history can never blow up a response.
 */

import { Container } from "@azure/cosmos";
import { HttpRequest, HttpResponseInit } from "@azure/functions";
import { SERVER_FIELDS } from "./contentHash";

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: HttpResponseInit };

function badRequest(message: string): HttpResponseInit {
  return { status: 400, jsonBody: { error: message } };
}

/**
 * Parses an optional integer query param, applying a default and a hard cap.
 * Non-numeric or non-positive values are rejected with 400; values above the
 * cap are clamped (bounded responses, not errors).
 */
export function parseLimit(
  request: HttpRequest,
  options: { name?: string; defaultValue: number; max: number }
): ParseResult<number> {
  const name = options.name ?? "limit";
  const raw = request.query.get(name);
  if (raw === null || raw === "") {
    return { ok: true, value: options.defaultValue };
  }
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 1) {
    return {
      ok: false,
      error: badRequest(`Invalid ${name}: must be a positive integer`),
    };
  }
  return { ok: true, value: Math.min(parsed, options.max) };
}

/**
 * Parses an optional ISO-8601 date query param. Returns undefined when absent;
 * rejects unparseable values with 400.
 */
export function parseIsoDate(
  request: HttpRequest,
  name: string,
  options?: { required?: boolean }
): ParseResult<string | undefined> {
  const raw = request.query.get(name);
  if (raw === null || raw === "") {
    if (options?.required) {
      return { ok: false, error: badRequest(`Missing required query param: ${name}`) };
    }
    return { ok: true, value: undefined };
  }
  if (Number.isNaN(Date.parse(raw))) {
    return {
      ok: false,
      error: badRequest(`Invalid ${name}: must be an ISO-8601 date`),
    };
  }
  return { ok: true, value: raw };
}

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Parses an optional date bound and normalizes it to `toISOString()` form.
 *
 * The mirror stores the phone's dates as UTC ISO strings and Cosmos compares
 * them as strings, so a bound has to be in the same form to compare
 * correctly: "2026-11-03T10:00:00+01:00" is normalized to 09:00Z. A date-only
 * `end` bound ("2026-11-03") covers that whole UTC day, which is what a
 * caller asking for "up to the 3rd" means; as a bare string it would sort
 * before every timestamp on the 3rd and silently drop that day.
 */
export function parseIsoDateBound(
  request: HttpRequest,
  name: string,
  bound: "start" | "end"
): ParseResult<string | undefined> {
  const raw = request.query.get(name);
  if (raw === null || raw === "") return { ok: true, value: undefined };
  const millis = Date.parse(raw);
  if (Number.isNaN(millis)) {
    return {
      ok: false,
      error: badRequest(`Invalid ${name}: must be an ISO-8601 date`),
    };
  }
  if (bound === "end" && DATE_ONLY.test(raw)) {
    return { ok: true, value: `${raw}T23:59:59.999Z` };
  }
  return { ok: true, value: new Date(millis).toISOString() };
}

/**
 * Returns a copy of a stored document as readers should see it: without
 * Cosmos system properties and without the snapshot push's server-owned
 * `mirrorContentHash`.
 */
export function stripSystemProps<T extends object>(doc: T): T {
  const clean: Record<string, unknown> = { ...(doc as Record<string, unknown>) };
  for (const field of SERVER_FIELDS) delete clean[field];
  return clean as T;
}

/**
 * Point-reads a document by id (id == partition key for all our containers).
 * Returns null on 404 — the SDK either resolves with an undefined resource or
 * throws with code 404 depending on version, so both are handled.
 */
export async function readItemOrNull<T>(
  container: Container,
  id: string
): Promise<T | null> {
  try {
    const { resource } = await container.item(id, id).read();
    return (resource as T | undefined) ?? null;
  } catch (err: unknown) {
    const code = (err as { code?: number | string }).code;
    if (code === 404 || code === "NotFound") return null;
    throw err;
  }
}
