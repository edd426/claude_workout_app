import { timingSafeEqual } from "node:crypto";

/**
 * Constant-time comparison of two secrets (#94).
 *
 * `timingSafeEqual` throws on a length mismatch, so lengths are checked
 * first and mismatches return early. That leaks the expected key's length,
 * which is not worth protecting: the value is high-entropy, and an attacker
 * who learns its length still has to guess it. What this does remove is the
 * byte-by-byte early exit of `===`, which leaks how much of a guess was
 * correct.
 *
 * Defence in depth rather than a live hole — a remote timing attack across
 * network jitter is impractical (see the issue's own severity note).
 *
 * Lives in its own module because `shared/auth` is globally stubbed in the
 * Jest config, so nothing inside it can be tested directly.
 */
export function secretsMatch(provided: string, expected: string): boolean {
  const providedBuffer = Buffer.from(provided, "utf8");
  const expectedBuffer = Buffer.from(expected, "utf8");
  if (providedBuffer.length !== expectedBuffer.length) return false;
  return timingSafeEqual(providedBuffer, expectedBuffer);
}
