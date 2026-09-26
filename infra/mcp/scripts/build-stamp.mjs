/**
 * Records what the compiled server was built from — issue #138.
 *
 * `dist/` is gitignored and the server is launched as `node dist/src/server.js`,
 * which runs no npm lifecycle script. So nothing ties the running server to the
 * committed source, and a stale `dist/` is invisible: #135's report tools
 * shipped in `src/` and simply did not exist in the running server.
 *
 * This writes the git HEAD and the newest source mtime at build time.
 * `buildInfo()` compares that against the live source tree, and `health()`
 * reports it — so `mcp__workout__health` answers "is this the committed
 * source?" instead of nobody asking.
 */

import { execFileSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

// The compiled copy — tsc has already run by this point in `npm run build`,
// so the stamp and the runtime check use literally the same code.
import { newestSourceMtime } from "../dist/src/shared/source-mtime.js";

const outputUrl = new URL("../dist/build-info.json", import.meta.url);
const repoRoot = new URL("../../../", import.meta.url);

function gitHead() {
  try {
    return execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: fileURLToPath(repoRoot),
      encoding: "utf8",
    }).trim();
  } catch {
    // A build outside a git checkout is legitimate; the mtime check still works.
    return null;
  }
}

function gitDirty() {
  try {
    const out = execFileSync("git", ["status", "--porcelain", "--", "infra/mcp/src"], {
      cwd: fileURLToPath(repoRoot),
      encoding: "utf8",
    });
    return out.trim().length > 0;
  } catch {
    return null;
  }
}

const info = {
  builtAt: new Date().toISOString(),
  gitHead: gitHead(),
  sourceDirtyAtBuild: gitDirty(),
  newestSourceMtimeMs: await newestSourceMtime(),
};

await mkdir(dirname(fileURLToPath(outputUrl)), { recursive: true });
await writeFile(fileURLToPath(outputUrl), JSON.stringify(info, null, 2) + "\n");
console.error(
  `build-stamp: ${info.gitHead ?? "(no git)"}${info.sourceDirtyAtBuild ? " (dirty)" : ""}`
);
