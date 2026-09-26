/**
 * Tests for constant-time secret comparison — issue #94.
 *
 * These pin the behaviour, not the timing: timing cannot be asserted
 * reliably in a unit test, and a test that tried would be flaky theatre.
 */

import { secretsMatch } from "../src/shared/secretCompare";

describe("secretsMatch", () => {
  test("accepts an exact match", () => {
    expect(secretsMatch("s3cret-key-value", "s3cret-key-value")).toBe(true);
  });

  test("rejects a wrong key of the same length", () => {
    expect(secretsMatch("s3cret-key-valuf", "s3cret-key-value")).toBe(false);
  });

  test("rejects a different length without throwing", () => {
    // timingSafeEqual throws on mismatched buffer lengths — without the
    // length guard, a short key would turn auth into a 500 instead of a 401.
    expect(() => secretsMatch("short", "s3cret-key-value")).not.toThrow();
    expect(secretsMatch("short", "s3cret-key-value")).toBe(false);
  });

  test("rejects a prefix of the real key", () => {
    expect(secretsMatch("s3cret", "s3cret-key-value")).toBe(false);
  });

  test("rejects the empty string", () => {
    expect(secretsMatch("", "s3cret-key-value")).toBe(false);
  });

  test("compares by bytes, not code units", () => {
    // Multi-byte characters must not confuse the length guard.
    expect(secretsMatch("kéy", "kéy")).toBe(true);
    expect(secretsMatch("key", "kéy")).toBe(false);
  });
});
