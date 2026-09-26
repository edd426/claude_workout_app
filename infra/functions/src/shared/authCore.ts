import { HttpRequest, HttpResponseInit } from "@azure/functions";
import { secretsMatch } from "./secretCompare";

// ─── Minimal in-memory failure throttle (issue #94) ────────────────────────
// Deliberately simple: per-instance, in-memory, no external storage or deps.
// After FAILURE_THRESHOLD consecutive failures, attempts are rejected with
// 429 for COOLDOWN_MS. The cooldown is time-based rather than
// success-based: a throttled request is rejected before its key is checked,
// so a permanent lockout could never be cleared by the legitimate client.

const FAILURE_THRESHOLD = 10;
const COOLDOWN_MS = 30_000;

let consecutiveFailures = 0;
let lastFailureAt = 0;

function recordAuthFailure(): void {
  consecutiveFailures += 1;
  lastFailureAt = Date.now();
}

function recordAuthSuccess(): void {
  consecutiveFailures = 0;
  lastFailureAt = 0;
}

export function isThrottled(now: number = Date.now()): boolean {
  return (
    consecutiveFailures >= FAILURE_THRESHOLD &&
    now - lastFailureAt < COOLDOWN_MS
  );
}

/** Test-only: reset in-memory throttle state between test cases. */
export function _resetThrottleState(): void {
  consecutiveFailures = 0;
  lastFailureAt = 0;
}

/**
 * The real authentication gate. Lives here (rather than in auth.ts) because
 * `../shared/auth` is globally mapped to a permissive test stub for every
 * other test file's convenience (see jest.config.js); this filename isn't,
 * so tests can exercise the actual implementation directly. auth.ts
 * re-exports this unchanged for production code to import.
 */
export function authenticateRequest(request: HttpRequest): HttpResponseInit | null {
  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    return {
      status: 500,
      jsonBody: { error: "Server misconfigured: API_KEY not set" },
    };
  }

  if (isThrottled()) {
    return {
      status: 429,
      jsonBody: {
        error: "Too many failed authentication attempts. Try again shortly.",
      },
    };
  }

  const providedKey = request.headers.get("x-api-key");
  if (!providedKey || !secretsMatch(providedKey, apiKey)) {
    recordAuthFailure();
    return {
      status: 401,
      jsonBody: { error: "Unauthorized: invalid or missing API key" },
    };
  }

  recordAuthSuccess();
  return null;
}
