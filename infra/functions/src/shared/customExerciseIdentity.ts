export const MAX_CUSTOM_EXERCISE_SLUG_LENGTH = 64;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function isValidCustomExerciseExternalId(
  externalId: string,
  operationId?: string
): boolean {
  const parts = externalId.split(":");
  if (parts.length !== 3 || parts[0] !== "custom") return false;
  const [, slug, suffix] = parts;
  if (
    slug.length === 0 ||
    slug.length > MAX_CUSTOM_EXERCISE_SLUG_LENGTH ||
    !SLUG_PATTERN.test(slug) ||
    !UUID_PATTERN.test(suffix)
  ) {
    return false;
  }
  return operationId === undefined ||
    suffix.toLowerCase() === operationId.toLowerCase();
}

export function customExerciseExternalId(
  name: string,
  operationId: string
): string {
  const normalized =
    name
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-zA-Z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .toLowerCase() || "exercise";
  const slug =
    normalized
      .slice(0, MAX_CUSTOM_EXERCISE_SLUG_LENGTH)
      .replace(/-+$/g, "") || "exercise";
  return `custom:${slug}:${operationId.toLowerCase()}`;
}
