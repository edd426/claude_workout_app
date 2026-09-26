/**
 * Tests for the real authentication gate — issue #94.
 *
 * jest.config.js maps "../shared/auth" to a permissive test stub so every
 * other test file can assume auth passes. auth.ts is a thin re-export of
 * authCore.authenticateRequest, and authCore.ts is NOT mapped — importing it
 * here (rather than "../src/shared/auth") gets the real, unmocked gate.
 */

import { HttpRequest } from "@azure/functions";
import { authenticateRequest, _resetThrottleState } from "../src/shared/authCore";

function makeRequest(apiKey: string | null) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(undefined, apiKey ? { "x-api-key": apiKey } : {});
}

describe("authenticateRequest — real implementation", () => {
  beforeEach(() => {
    process.env.API_KEY = "correct-key";
    _resetThrottleState();
  });

  test("wrong API key is rejected with 401", () => {
    const result = authenticateRequest(makeRequest("wrong-key"));
    expect(result?.status).toBe(401);
  });

  test("missing API key is rejected with 401", () => {
    const result = authenticateRequest(makeRequest(null));
    expect(result?.status).toBe(401);
  });

  test("correct API key passes (returns null)", () => {
    const result = authenticateRequest(makeRequest("correct-key"));
    expect(result).toBeNull();
  });

  test("throttles after repeated failures", () => {
    for (let i = 0; i < 10; i++) authenticateRequest(makeRequest("wrong-key"));
    const result = authenticateRequest(makeRequest("correct-key"));
    expect(result?.status).toBe(429);
  });

  test("a success resets the throttle so the next failure isn't immediately throttled", () => {
    authenticateRequest(makeRequest("correct-key"));
    for (let i = 0; i < 9; i++) authenticateRequest(makeRequest("wrong-key"));
    const result = authenticateRequest(makeRequest("wrong-key"));
    expect(result?.status).toBe(401);
  });
});
