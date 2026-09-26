import { HttpRequest, HttpResponseInit } from "@azure/functions";
import { authenticateRequest } from "./authCore";

/**
 * Validates the x-api-key header against the API_KEY environment variable.
 * Returns null if authentication passes, or an error response if it fails.
 *
 * Issue #94: comparison is constant-time and repeated consecutive failures
 * are throttled in-memory. See ./authCore for the implementation and
 * tests/auth.test.ts for coverage of the real (unmocked) behavior.
 */
export function authenticate(request: HttpRequest): HttpResponseInit | null {
  return authenticateRequest(request);
}
