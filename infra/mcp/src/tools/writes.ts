import { apiDelete, apiGet, apiPost } from "../shared/http.js";
import {
  resolveExerciseByExternalId,
  searchCatalog,
} from "./catalog.js";

export type InboxOperationType =
  | "createTemplate"
  | "updateTemplate"
  | "deleteTemplate"
  | "createCustomExercise";

export type InboxOperationStatus =
  | "pending"
  | "awaitingApproval"
  | "applied"
  | "rejected"
  | "failed";

export interface TemplateExerciseWrite {
  externalId: string;
  order: number;
  defaultSets: number;
  defaultReps: number;
  defaultWeight?: number;
  defaultRestSeconds?: number;
  notes?: string;
  /**
   * Issue #169: substitutes for this slot, in order. Tri-state on the phone:
   * absent keeps the slot's current list (update), [] clears it, a list
   * replaces it. An absent key must therefore stay absent, never become [].
   */
  alternatives?: AlternativeWrite[];
}

export interface AlternativeWrite {
  externalId: string;
  note?: string;
}

export interface CreateTemplatePayload {
  name: string;
  notes?: string;
  exercises: TemplateExerciseWrite[];
}

export interface UpdateTemplatePayload {
  id: string;
  name?: string;
  notes?: string;
  exercises?: TemplateExerciseWrite[];
}

export interface DeleteTemplatePayload {
  id: string;
  name: string;
}

export interface CreateCustomExercisePayload {
  name: string;
  equipment?: string;
  primaryMuscles?: string[];
  secondaryMuscles?: string[];
  instructions?: string[];
  notes?: string;
}

export interface InboxOperation {
  id: string;
  createdAt: string;
  op: InboxOperationType;
  payload: Record<string, unknown>;
  requiresApproval: boolean;
  status: InboxOperationStatus;
  appliedAt?: string;
  error?: string;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${field} must be a non-empty string`);
  }
  return value;
}

function optionalString(value: unknown, field: string): void {
  if (value !== undefined && typeof value !== "string") {
    throw new Error(`${field} must be a string`);
  }
}

function optionalStringArray(value: unknown, field: string): void {
  if (
    value !== undefined &&
    (!Array.isArray(value) ||
      !value.every((entry) => typeof entry === "string"))
  ) {
    throw new Error(`${field} must be a string array`);
  }
}

/** The error for an externalId that resolves nowhere, with catalog suggestions. */
export function unknownExternalIdError(externalId: string, field?: string): Error {
  const humanized = externalId.replace(/[_:/-]+/g, " ");
  const suggestions = searchCatalog(humanized, 3)
    .map((exercise) => `${exercise.name} (${exercise.externalId})`)
    .join(", ");
  return new Error(
    `${field ? `${field}: ` : ""}Unknown externalId "${externalId}". ` +
      `Suggestions: ${suggestions}. ` +
      "Call search_exercises and use an exact externalId from its results."
  );
}

async function assertKnownExternalId(
  externalId: string,
  field?: string
): Promise<void> {
  if (await resolveExerciseByExternalId(externalId)) return;
  throw unknownExternalIdError(externalId, field);
}

/**
 * Validates one exercise's `alternatives` and returns them reduced to exactly
 * the keys the phone reads, `{ externalId, note? }`. Every externalId resolves
 * against the catalog (bundled or custom) the same way the main exercise does.
 * `null` is refused: it is ambiguous between "keep" (omit) and "clear" ([]).
 */
async function validateAlternatives(
  value: unknown,
  field: string
): Promise<AlternativeWrite[]> {
  if (!Array.isArray(value)) {
    throw new Error(
      `${field} must be an array (omit it to keep the current list, [] to clear it)`
    );
  }
  const alternatives: AlternativeWrite[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const path = `${field}[${index}]`;
    const alternative = value[index];
    if (!isObject(alternative)) throw new Error(`${path} must be an object`);
    const externalId = nonEmptyString(alternative["externalId"], `${path}.externalId`);
    optionalString(alternative["note"], `${path}.note`);
    await assertKnownExternalId(externalId, path);
    const note = alternative["note"] as string | undefined;
    alternatives.push(note === undefined ? { externalId } : { externalId, note });
  }
  return alternatives;
}

async function validateTemplateExercises(
  value: unknown,
  field: string
): Promise<TemplateExerciseWrite[]> {
  if (!Array.isArray(value)) {
    throw new Error(`${field} must be an array`);
  }

  const validated: TemplateExerciseWrite[] = [];
  const orders = new Set<number>();
  for (let index = 0; index < value.length; index += 1) {
    const exercise = value[index];
    const path = `${field}[${index}]`;
    if (!isObject(exercise)) {
      throw new Error(`${path} must be an object`);
    }

    const externalId = nonEmptyString(
      exercise["externalId"],
      `${path}.externalId`
    );
    const order = exercise["order"];
    if (!Number.isInteger(order) || (order as number) < 0) {
      throw new Error(`${path}.order must be a non-negative integer`);
    }
    if (orders.has(order as number)) {
      throw new Error(`${field} contains duplicate order ${String(order)}`);
    }
    orders.add(order as number);

    for (const fieldName of ["defaultSets", "defaultReps"] as const) {
      const fieldValue = exercise[fieldName];
      if (!Number.isInteger(fieldValue) || (fieldValue as number) <= 0) {
        throw new Error(`${path}.${fieldName} must be a positive integer`);
      }
    }

    const weight = exercise["defaultWeight"];
    if (
      weight !== undefined &&
      (typeof weight !== "number" || !Number.isFinite(weight))
    ) {
      throw new Error(`${path}.defaultWeight must be a finite number`);
    }
    const restSeconds = exercise["defaultRestSeconds"];
    if (
      restSeconds !== undefined &&
      (!Number.isInteger(restSeconds) || (restSeconds as number) < 0)
    ) {
      throw new Error(
        `${path}.defaultRestSeconds must be a non-negative integer`
      );
    }
    optionalString(exercise["notes"], `${path}.notes`);

    // Resolution must finish before the caller performs the template POST.
    await assertKnownExternalId(externalId);

    const written = { ...exercise } as unknown as TemplateExerciseWrite;
    if (Object.prototype.hasOwnProperty.call(exercise, "alternatives")) {
      written.alternatives = await validateAlternatives(
        exercise["alternatives"],
        `${path}.alternatives`
      );
    }
    validated.push(written);
  }

  return validated;
}

async function validateCreateTemplate(
  value: unknown,
  field = "template"
): Promise<CreateTemplatePayload> {
  if (!isObject(value)) throw new Error(`${field} must be an object`);
  nonEmptyString(value["name"], `${field}.name`);
  optionalString(value["notes"], `${field}.notes`);
  const exercises = await validateTemplateExercises(
    value["exercises"],
    `${field}.exercises`
  );
  return { ...value, exercises } as unknown as CreateTemplatePayload;
}

async function validateUpdateTemplate(
  value: unknown
): Promise<UpdateTemplatePayload> {
  if (!isObject(value)) throw new Error("updateTemplate payload must be an object");
  nonEmptyString(value["id"], "updateTemplate.id");
  if (value["name"] !== undefined) {
    nonEmptyString(value["name"], "updateTemplate.name");
  }
  optionalString(value["notes"], "updateTemplate.notes");
  if (value["exercises"] !== undefined) {
    const exercises = await validateTemplateExercises(
      value["exercises"],
      "updateTemplate.exercises"
    );
    return { ...value, exercises } as unknown as UpdateTemplatePayload;
  }
  return value as unknown as UpdateTemplatePayload;
}

function validateDeleteTemplate(value: unknown): DeleteTemplatePayload {
  if (!isObject(value)) throw new Error("deleteTemplate payload must be an object");
  nonEmptyString(value["id"], "deleteTemplate.id");
  nonEmptyString(value["name"], "deleteTemplate.name");
  return value as unknown as DeleteTemplatePayload;
}

function validateCreateCustomExercise(
  value: unknown
): CreateCustomExercisePayload {
  if (!isObject(value)) {
    throw new Error("createCustomExercise payload must be an object");
  }
  nonEmptyString(value["name"], "createCustomExercise.name");
  optionalString(value["equipment"], "createCustomExercise.equipment");
  optionalStringArray(
    value["primaryMuscles"],
    "createCustomExercise.primaryMuscles"
  );
  optionalStringArray(
    value["secondaryMuscles"],
    "createCustomExercise.secondaryMuscles"
  );
  optionalStringArray(
    value["instructions"],
    "createCustomExercise.instructions"
  );
  optionalString(value["notes"], "createCustomExercise.notes");
  return value as unknown as CreateCustomExercisePayload;
}

async function enqueue(
  op: InboxOperationType,
  payload:
    | CreateTemplatePayload
    | UpdateTemplatePayload
    | DeleteTemplatePayload
    | CreateCustomExercisePayload
): Promise<InboxOperation> {
  return apiPost<InboxOperation>("inbox", { op, payload });
}

export async function createTemplate(
  payload: unknown
): Promise<InboxOperation> {
  return enqueue("createTemplate", await validateCreateTemplate(payload));
}

export async function updateTemplate(
  payload: unknown
): Promise<InboxOperation> {
  return enqueue("updateTemplate", await validateUpdateTemplate(payload));
}

export async function deleteTemplate(
  payload: unknown
): Promise<InboxOperation> {
  return enqueue("deleteTemplate", validateDeleteTemplate(payload));
}

export async function createProgram(
  value: unknown
): Promise<InboxOperation[]> {
  if (!isObject(value) || !Array.isArray(value["templates"])) {
    throw new Error("templates must be an array");
  }

  // Validate every payload—including every externalId—before the first POST.
  const templates: CreateTemplatePayload[] = [];
  for (let index = 0; index < value["templates"].length; index += 1) {
    templates.push(
      await validateCreateTemplate(
        value["templates"][index],
        `templates[${index}]`
      )
    );
  }

  const operations: InboxOperation[] = [];
  for (const template of templates) {
    operations.push(await enqueue("createTemplate", template));
  }
  return operations;
}

export async function createCustomExercise(
  payload: unknown
): Promise<InboxOperation> {
  return enqueue(
    "createCustomExercise",
    validateCreateCustomExercise(payload)
  );
}

export async function listPendingWrites(options: {
  status?: string;
} = {}): Promise<InboxOperation[]> {
  const statuses: readonly string[] = [
    "pending",
    "awaitingApproval",
    "applied",
    "rejected",
    "failed",
  ];
  if (options.status !== undefined && !statuses.includes(options.status)) {
    throw new Error(`Unknown inbox status: ${options.status}`);
  }

  const response = await apiGet<{ operations: InboxOperation[] }>("inbox", {
    status: options.status,
  });
  return response.operations;
}

/**
 * Deletes one or more terminal inbox operations (issue #148). The Functions
 * API is the source of truth for what "terminal" means and refuses
 * pending/awaitingApproval operations with 409 — this layer only validates
 * ids and enforces all-or-nothing on the id list itself before making any
 * request, exactly like `resolveExerciseReport`.
 *
 * Takes either `id` (deletes one) or `ids` (deletes several). A failure part
 * way through a batch is surfaced immediately — batch-mates before the
 * failing id have already been deleted server-side, and mates after it are
 * never attempted, so the caller sees exactly what changed.
 */
export async function deleteInboxOperation(
  args: unknown
): Promise<{ deleted: string[] }> {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    throw new Error("Arguments must be an object");
  }
  const input = args as Record<string, unknown>;

  const rawId = input["id"];
  const rawIds = input["ids"];
  if (rawId !== undefined && rawIds !== undefined) {
    throw new Error("Pass either id or ids, not both");
  }

  const isBatch = rawIds !== undefined;
  if (isBatch && !Array.isArray(rawIds)) {
    throw new Error("ids must be an array of inbox operation ids");
  }
  const ids = isBatch ? (rawIds as unknown[]) : [rawId];
  if (ids.length === 0) {
    throw new Error("ids must contain at least one inbox operation id");
  }
  for (const candidate of ids) {
    if (typeof candidate !== "string" || candidate.trim().length === 0) {
      throw new Error("id must be a non-empty string");
    }
  }

  const deleted: string[] = [];
  for (const id of ids as string[]) {
    await apiDelete(`inbox/${id}`);
    deleted.push(id);
  }
  return { deleted };
}
