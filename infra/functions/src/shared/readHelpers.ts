/**
 * Shared request-validation and Cosmos point-read helpers for the read-only
 * API endpoints (issue #79). All query inputs are validated and bounded so a
 * huge history can never blow up a response.
 */

import { Container } from "@azure/cosmos";
import { HttpRequest, HttpResponseInit } from "@azure/functions";

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
