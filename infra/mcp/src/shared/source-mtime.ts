/**
 * Newest mtime across everything the compiled server is built from (#138).
 *
 * TypeScript rather than a plain .mjs so `tsc` actually emits it into `dist/` —
 * a `.mjs` here compiles fine and then is silently absent at runtime, which is
 * the same invisible-staleness failure this guard exists to catch.
 *
 * The build stamper imports the *compiled* copy of this module, so the mtime
 * recorded at build time and the mtime checked at runtime come from one
 * definition and cannot drift apart.
 *
 * Covers `src/` and the exercise catalog, which feeds `dist/catalog-index.json`
 * and is just as capable of going stale.
 */

import { readdir, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";

/**
 * The real inputs of the build: `infra/mcp/src` and the app's exercise catalog.
 * Never `dist/`: compiled output is not source, and on the deployed Function
 * App (which ships dist/ only, per .funcignore) its mtimes are the instance's
 * start time, which made every cold start report a stale build. There, neither
 * root exists, so the check finds nothing newer than the build and stays quiet.
 */
export function sourceRootsFor(moduleUrl: string): string[] {
  // This module is src/shared/source-mtime.ts (two levels below the package
  // root) or dist/src/shared/source-mtime.js (three levels).
  const compiled = new URL(moduleUrl).pathname.includes("/dist/src/shared/");
  const packageRoot = new URL(compiled ? "../../../" : "../../", moduleUrl);
  const roots = [
    new URL("src", packageRoot),
    new URL("../../ClaudeLifter/Resources/exercises.json", packageRoot),
  ];
  return roots.map((url) => fileURLToPath(url).replace(/\/$/, ""));
}

function sourceRoots(): string[] {
  return sourceRootsFor(import.meta.url);
}

async function newestUnder(path: string): Promise<number> {
  let info;
  try {
    info = await stat(path);
  } catch {
    return 0;
  }
  if (!info.isDirectory()) return info.mtimeMs;

  const entries = await readdir(path, { withFileTypes: true });
  const times = await Promise.all(
    entries.map((entry) => newestUnder(`${path}/${entry.name}`))
  );
  return times.reduce((max, t) => (t > max ? t : max), 0);
}

export async function newestSourceMtime(): Promise<number> {
  const times = await Promise.all(sourceRoots().map(newestUnder));
  return times.reduce((max, t) => (t > max ? t : max), 0);
}
