/**
 * Is the running server the committed source? — issue #138.
 *
 * `dist/` is gitignored, so there is nothing to diff in CI, and the launch
 * command (`node dist/src/server.js`) runs no npm script. The only place a
 * stale build can be caught is at runtime, in the process that is actually
 * serving. #135's report tools existed in `src/` and were absent from the
 * running server for a whole day because nobody could see the difference.
 */

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { newestSourceMtime } from "./source-mtime.js";

export interface BuildInfo {
  builtAt: string | null;
  gitHead: string | null;
  sourceDirtyAtBuild: boolean | null;
  newestSourceMtimeMs: number | null;
}

export interface BuildFreshness extends BuildInfo {
  /** True when source has been touched since the build that is running. */
  stale: boolean;
  /** Human-readable reason, or null when the build is current. */
  staleReason: string | null;
}

function infoPath(): string | null {
  const candidates = [
    // Compiled runtime: dist/src/shared/build-info.js -> dist/build-info.json
    new URL("../../build-info.json", import.meta.url),
    // Vitest source runtime: src/shared/build-info.ts -> dist/build-info.json
    new URL("../../dist/build-info.json", import.meta.url),
  ];
  const found = candidates.find((c) => existsSync(fileURLToPath(c)));
  return found ? fileURLToPath(found) : null;
}

export function readBuildInfo(): BuildInfo | null {
  const path = infoPath();
  if (!path) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8")) as BuildInfo;
  } catch {
    return null;
  }
}

export async function buildFreshness(): Promise<BuildFreshness> {
  const info = readBuildInfo();
  if (!info) {
    return {
      builtAt: null,
      gitHead: null,
      sourceDirtyAtBuild: null,
      newestSourceMtimeMs: null,
      stale: true,
      staleReason:
        "No dist/build-info.json — this server was built before the staleness " +
        "guard existed, or dist/ is incomplete. Run npm run build in infra/mcp.",
    };
  }

  const newest = await newestSourceMtime();
  const builtFrom = info.newestSourceMtimeMs ?? 0;
  // One second of slack: mtimes have coarse granularity on some filesystems,
  // and a build touching its own inputs should not report itself stale.
  if (newest > builtFrom + 1000) {
    const drift = Math.round((newest - builtFrom) / 1000);
    return {
      ...info,
      stale: true,
      staleReason:
        `Source has changed since this build (newest source is ${drift}s ` +
        `newer than what dist/ was built from). The running server does not ` +
        `include those changes. Run npm run build in infra/mcp and restart ` +
        `the MCP client.`,
    };
  }

  return { ...info, stale: false, staleReason: null };
}
