/**
 * #138 — the guard that answers "is the running server the committed source?"
 *
 * These assert the property that actually failed in practice: a build that is
 * older than its source must report itself stale. A guard that never fires is
 * indistinguishable from no guard, which is what we had.
 */

import { describe, it, expect } from "vitest";
import { existsSync, utimesSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { readBuildInfo, buildFreshness } from "../src/shared/build-info.js";
import { newestSourceMtime, sourceRootsFor } from "../src/shared/source-mtime.js";

describe("source roots", () => {
  const pkg = "/x/repo/infra/mcp";
  const expected = [`${pkg}/src`, "/x/repo/ClaudeLifter/Resources/exercises.json"];

  // The deployed Function App ships dist/ only (.funcignore drops src/), and
  // its files carry the instance's start time as mtime. Counting dist/src as
  // "source" made every cold start report a stale build (2026-11-03).
  it("from the compiled module are the real sources, never dist/", () => {
    expect(sourceRootsFor(`file://${pkg}/dist/src/shared/source-mtime.js`)).toEqual(expected);
  });

  it("from the TypeScript module are the same paths", () => {
    expect(sourceRootsFor(`file://${pkg}/src/shared/source-mtime.ts`)).toEqual(expected);
  });
});

const buildInfoPath = fileURLToPath(
  new URL("../dist/build-info.json", import.meta.url)
);

describe("build info", () => {
  it("is written by the build", () => {
    expect(existsSync(buildInfoPath)).toBe(true);
    const info = readBuildInfo();
    expect(info).not.toBeNull();
    expect(info?.builtAt).toBeTruthy();
  });

  it("sees the source tree", async () => {
    const newest = await newestSourceMtime();
    expect(newest).toBeGreaterThan(0);
  });

  it("reports stale when a source file is newer than the build", async () => {
    // Push one source file into the future rather than rebuilding — the
    // assertion is about the comparison, and this leaves dist/ alone.
    const target = fileURLToPath(new URL("../src/registry.ts", import.meta.url));
    const original = statSync(target);
    const future = new Date(Date.now() + 60_000);
    try {
      utimesSync(target, future, future);
      const freshness = await buildFreshness();
      expect(freshness.stale).toBe(true);
      expect(freshness.staleReason).toMatch(/npm run build/);
    } finally {
      utimesSync(target, original.atime, original.mtime);
    }
  });

  it("reports fresh for a build newer than every source file", async () => {
    const freshness = await buildFreshness();
    // The suite runs against a just-built dist/; if this fails, run npm run build.
    expect(freshness.stale).toBe(false);
    expect(freshness.staleReason).toBeNull();
  });
});
