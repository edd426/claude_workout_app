import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { isValidCustomExerciseExternalId } from "../shared/customExerciseIdentity.js";
import { apiGet } from "../shared/http.js";

export interface CatalogExercise {
  externalId: string;
  name: string;
  primaryMuscles: string[];
  equipment: string | null;
  category: string | null;
}

export interface ExerciseSearchResult {
  externalId: string;
  name: string;
  primaryMuscles: string[];
  equipment: string | null;
}

interface SnapshotReadResponse {
  snapshot?: {
    customExercises?: unknown[];
  };
}

interface InboxListResponse {
  operations?: {
    id?: unknown;
    op?: unknown;
    payload?: unknown;
  }[];
}

let cachedCatalog: CatalogExercise[] | undefined;
let cachedByExternalId: Map<string, CatalogExercise> | undefined;

function indexPath(): string {
  const candidates = [
    // Compiled runtime: dist/src/tools/catalog.js -> dist/catalog-index.json
    new URL("../../catalog-index.json", import.meta.url),
    // Vitest source runtime: src/tools/catalog.ts -> dist/catalog-index.json
    new URL("../../dist/catalog-index.json", import.meta.url),
  ];
  const found = candidates.find((candidate) =>
    existsSync(fileURLToPath(candidate))
  );
  if (!found) {
    throw new Error(
      "Catalog index is missing. Run npm run build (or the catalog builder) first."
    );
  }
  return fileURLToPath(found);
}

function isCatalogExercise(value: unknown): value is CatalogExercise {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const exercise = value as Record<string, unknown>;
  return (
    typeof exercise["externalId"] === "string" &&
    typeof exercise["name"] === "string" &&
    Array.isArray(exercise["primaryMuscles"]) &&
    exercise["primaryMuscles"].every((muscle) => typeof muscle === "string") &&
    (typeof exercise["equipment"] === "string" ||
      exercise["equipment"] === null) &&
    (typeof exercise["category"] === "string" ||
      exercise["category"] === null)
  );
}

export function loadCatalog(): CatalogExercise[] {
  if (cachedCatalog) return cachedCatalog;

  const parsed = JSON.parse(readFileSync(indexPath(), "utf8")) as unknown;
  if (!Array.isArray(parsed) || !parsed.every(isCatalogExercise)) {
    throw new Error("Catalog index has an invalid shape; rebuild it");
  }

  cachedCatalog = parsed;
  cachedByExternalId = new Map(
    parsed.map((exercise) => [exercise.externalId, exercise])
  );
  return cachedCatalog;
}

export function findExerciseByExternalId(
  externalId: string
): CatalogExercise | undefined {
  loadCatalog();
  return cachedByExternalId?.get(externalId);
}

export async function resolveExerciseByExternalId(
  externalId: string
): Promise<CatalogExercise | undefined> {
  const bundled = findExerciseByExternalId(externalId);
  if (bundled) return bundled;
  if (!externalId.startsWith("custom:")) return undefined;
  if (!isValidCustomExerciseExternalId(externalId)) return undefined;

  const snapshot = await apiGet<SnapshotReadResponse>("sync/snapshot");
  const synced = (snapshot.snapshot?.customExercises ?? [])
    .map((exercise) => customExercise(exercise))
    .find((exercise) => exercise?.externalId === externalId);
  if (synced) return synced;

  for (const status of ["pending", "applied"] as const) {
    const inbox = await apiGet<InboxListResponse>("inbox", { status });
    const queued = (inbox.operations ?? [])
      .filter((operation) => operation.op === "createCustomExercise")
      .map((operation) =>
        customExercise(
          operation.payload,
          typeof operation.id === "string" ? operation.id : undefined
        )
      )
      .find((exercise) => exercise?.externalId === externalId);
    if (queued) return queued;
  }
  return undefined;
}

function normalize(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[_:/-]+/g, " ")
    .replace(/[^a-zA-Z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function levenshtein(left: string, right: string): number {
  if (left.length === 0) return right.length;
  if (right.length === 0) return left.length;

  let previous = Array.from(
    { length: right.length + 1 },
    (_, index) => index
  );
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    const current = [leftIndex];
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const substitution =
        previous[rightIndex - 1] +
        (left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1);
      current[rightIndex] = Math.min(
        previous[rightIndex] + 1,
        current[rightIndex - 1] + 1,
        substitution
      );
    }
    previous = current;
  }
  return previous[right.length];
}

function nameScore(name: string, query: string): number {
  const normalizedName = normalize(name);
  const normalizedQuery = normalize(query);
  if (normalizedQuery.length === 0) return 0;
  if (normalizedName === normalizedQuery) return 10_000;

  const nameWords = normalizedName.split(" ");
  const queryWords = normalizedQuery.split(" ");
  if (normalizedName.startsWith(normalizedQuery)) return 9_000;
  const substringIndex = normalizedName.indexOf(normalizedQuery);
  if (substringIndex >= 0) return 8_000 - substringIndex;

  const allWordsMatch = queryWords.every((queryWord) =>
    nameWords.some((nameWord) => nameWord.startsWith(queryWord))
  );
  if (allWordsMatch) {
    return (
      7_000 +
      queryWords.reduce(
        (score, queryWord) =>
          score +
          Math.max(
            ...nameWords.map((nameWord) =>
              nameWord === queryWord ? 100 : nameWord.startsWith(queryWord) ? 50 : 0
            )
          ),
        0
      )
    );
  }

  const distance = levenshtein(normalizedName, normalizedQuery);
  const maxLength = Math.max(normalizedName.length, normalizedQuery.length);
  return maxLength === 0 ? 0 : 1_000 * (1 - distance / maxLength);
}

export function rankExercises(
  exercises: readonly CatalogExercise[],
  query: string,
  limit = 10
): CatalogExercise[] {
  return exercises
    .map((exercise) => ({
      exercise,
      score: nameScore(exercise.name, query),
    }))
    .sort(
      (left, right) =>
        right.score - left.score ||
        left.exercise.name.localeCompare(right.exercise.name)
    )
    .slice(0, Math.max(0, limit))
    .map(({ exercise }) => exercise);
}

export function searchCatalog(query: string, limit = 10): CatalogExercise[] {
  return rankExercises(loadCatalog(), query, limit);
}

function customExercise(
  value: unknown,
  operationId?: string
): CatalogExercise | undefined {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  const exercise = value as Record<string, unknown>;
  const storedId = operationId ?? exercise["id"];
  const externalId = exercise["externalId"];
  const name = exercise["name"];
  if (
    typeof externalId !== "string" ||
    typeof storedId !== "string" ||
    !isValidCustomExerciseExternalId(externalId, storedId) ||
    typeof name !== "string" ||
    name.length === 0
  ) {
    return undefined;
  }
  const primaryMuscles = exercise["primaryMuscles"];
  const equipment = exercise["equipment"];
  return {
    externalId,
    name,
    primaryMuscles:
      Array.isArray(primaryMuscles) &&
      primaryMuscles.every((muscle) => typeof muscle === "string")
        ? primaryMuscles
        : [],
    equipment: typeof equipment === "string" ? equipment : null,
    category: "custom",
  };
}

export async function searchExercises(
  query: string,
  limit = 10
): Promise<ExerciseSearchResult[]> {
  const response = await apiGet<SnapshotReadResponse>("sync/snapshot");
  const custom = (response.snapshot?.customExercises ?? [])
    .map((exercise) => customExercise(exercise))
    .filter((exercise): exercise is CatalogExercise => exercise !== undefined);

  const byExternalId = new Map(
    [...loadCatalog(), ...custom].map((exercise) => [
      exercise.externalId,
      exercise,
    ])
  );

  return rankExercises([...byExternalId.values()], query, limit).map(
    ({ externalId, name, primaryMuscles, equipment }) => ({
      externalId,
      name,
      primaryMuscles,
      equipment,
    })
  );
}
