import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const sourceUrl = new URL(
  "../../../ClaudeLifter/Resources/exercises.json",
  import.meta.url
);
const outputUrl = new URL("../dist/catalog-index.json", import.meta.url);

const source = JSON.parse(await readFile(sourceUrl, "utf8"));
if (!Array.isArray(source)) {
  throw new Error("Exercise catalog source must be a JSON array");
}

const index = source.map((exercise, index) => {
  if (
    exercise === null ||
    typeof exercise !== "object" ||
    typeof exercise.id !== "string" ||
    exercise.id.length === 0 ||
    typeof exercise.name !== "string" ||
    !Array.isArray(exercise.primaryMuscles)
  ) {
    throw new Error(`Malformed exercise catalog entry at index ${index}`);
  }

  return {
    externalId: exercise.id,
    name: exercise.name,
    primaryMuscles: exercise.primaryMuscles,
    equipment: exercise.equipment ?? null,
    category: exercise.category ?? null,
  };
});

await mkdir(dirname(fileURLToPath(outputUrl)), { recursive: true });
await writeFile(outputUrl, `${JSON.stringify(index)}\n`, "utf8");

console.log(
  `Built ${fileURLToPath(outputUrl)} with ${index.length} exercises`
);
