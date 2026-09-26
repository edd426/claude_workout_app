/**
 * Tests for src/shared/authCore.ts — issue #94
 *
 * `../src/shared/auth` is globally mapped to a permissive test stub (see
 * jest.config.js), so the real throttle logic lives in a separately-named
 * module (authCore.ts) that isn't intercepted by that mapping and can be
 * exercised directly here. The constant-time comparison itself is
 * secretCompare.ts, covered by its own tests.
 */

import { HttpRequest } from "@azure/functions";
import {
  authenticateRequest,
  isThrottled,
  _resetThrottleState,
} from "../src/shared/authCore";

function requestWithKey(key: string | null): HttpRequest {
  return {
    headers: {
      get: (name: string) => (name === "x-api-key" ? key : null),
    },
  } as unknown as HttpRequest;
}

describe("failure throttle", () => {
  beforeEach(() => {
    _resetThrottleState();
    process.env.API_KEY = "the-right-key";
  });

  test("is not throttled before the failure threshold", () => {
    for (let i = 0; i < 9; i++) authenticateRequest(requestWithKey("wrong"));
    expect(isThrottled()).toBe(false);
    expect(authenticateRequest(requestWithKey("the-right-key"))).toBeNull();
  });

  test("throttles with 429 after 10 consecutive failures", () => {
    for (let i = 0; i < 10; i++) authenticateRequest(requestWithKey("wrong"));
    expect(isThrottled()).toBe(true);
    const result = authenticateRequest(requestWithKey("the-right-key"));
    expect(result?.status).toBe(429);
  });

  test("a success before the threshold resets the failure count", () => {
    for (let i = 0; i < 9; i++) authenticateRequest(requestWithKey("wrong"));
    expect(authenticateRequest(requestWithKey("the-right-key"))).toBeNull();
    for (let i = 0; i < 9; i++) authenticateRequest(requestWithKey("wrong"));
    expect(isThrottled()).toBe(false);
  });

  test("the throttle expires after the cooldown, so the real client is never locked out permanently", () => {
    for (let i = 0; i < 10; i++) authenticateRequest(requestWithKey("wrong"));
    expect(isThrottled()).toBe(true);
    // 31s later the cooldown has lapsed and a correct key gets through.
    expect(isThrottled(Date.now() + 31_000)).toBe(false);
  });

  test("missing key counts as a failure and returns 401", () => {
    const result = authenticateRequest(requestWithKey(null));
    expect(result?.status).toBe(401);
  });
});
