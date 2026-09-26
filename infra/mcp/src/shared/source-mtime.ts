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

function sourceRoots(): string[] {
  // Resolved relative to this module, which sits at either
  // src/shared/source-mtime.ts or dist/src/shared/source-mtime.js — both are
  // two levels below the package root.
  const packageRoot = new URL("../../", import.meta.url);
  const fromDist = new URL("../../../", import.meta.url);
  const roots = [
    new URL("src", packageRoot),
    new URL("src", fromDist),
    new URL("../../ClaudeLifter/Resources/exercises.json", packageRoot),
    new URL("../../../ClaudeLifter/Resources/exercises.json", fromDist),
  ];
  return roots.map((url) => fileURLToPath(url).replace(/\/$/, ""));
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
