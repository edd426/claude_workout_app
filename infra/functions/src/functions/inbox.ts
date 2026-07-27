/**
 * Durable MCP write inbox (issue #88).
 *
 * POST /api/inbox
 *   Validates one operation completely, assigns its server-owned envelope,
 *   and creates it in the Cosmos `inbox` container.
 *
 * GET /api/inbox
 *   Returns all operations for one status (pending by default), oldest first.
 *   Cosmos query pages are consumed to exhaustion.
 *
 * POST /api/inbox/ack
 *   Advances operation statuses. Existing terminal operations are idempotent
 *   no-ops, and unknown ids are counted rather than treated as server errors.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { Container } from "@azure/cosmos";
import { randomUUID } from "node:crypto";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { readItemOrNull } from "../shared/readHelpers";
import {
  InboxAckCounts,
  InboxAckRequest,
  InboxAckResponse,
  InboxAckResult,
  InboxAckStatus,
  InboxEnqueueRequest,
  InboxEnqueueResponse,
  InboxListResponse,
  InboxOperation,
  InboxOperationPayload,
  InboxOperationStatus,
  InboxOperationType,
} from "../shared/types";

const INBOX_CONTAINER = "inbox";
const PAGE_SIZE = 100;

const OPERATION_TYPES: readonly InboxOperationType[] = [
  "createTemplate",
  "updateTemplate",
  "deleteTemplate",
  "createCustomExercise",
];

const OPERATION_STATUSES: readonly InboxOperationStatus[] = [
  "pending",
  "awaitingApproval",
  "applied",
  "rejected",
  "failed",
];

const ACK_STATUSES: readonly InboxAckStatus[] = [
  "awaitingApproval",
  "applied",
  "rejected",
  "failed",
];

const TERMINAL_STATUSES = new Set<InboxOperationStatus>([
  "applied",
  "rejected",
  "failed",
]);

const COSMOS_SYSTEM_PROPS = ["_rid", "_self", "_etag", "_attachments", "_ts"];

function badRequest(message: string): HttpResponseInit {
  return { status: 400, jsonBody: { error: message } };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isOptionalString(value: unknown): value is string | undefined {
  return value === undefined || typeof value === "string";
}

function isOptionalStringArray(value: unknown): value is string[] | undefined {
  return (
    value === undefined ||
    (Array.isArray(value) && value.every((entry) => typeof entry === "string"))
  );
}

function isPositiveInteger(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) > 0;
}

function isOptionalFiniteNumber(value: unknown): value is number | undefined {
  return value === undefined || (typeof value === "number" && Number.isFinite(value));
}

function isOperationType(value: unknown): value is InboxOperationType {
  return (
    typeof value === "string" &&
    OPERATION_TYPES.includes(value as InboxOperationType)
  );
}

function isOperationStatus(value: unknown): value is InboxOperationStatus {
  return (
    typeof value === "string" &&
    OPERATION_STATUSES.includes(value as InboxOperationStatus)
  );
}

function isAckStatus(value: unknown): value is InboxAckStatus {
  return (
    typeof value === "string" && ACK_STATUSES.includes(value as InboxAckStatus)
  );
}

function validateTemplateExercises(
  value: unknown,
  field: string
): HttpResponseInit | null {
  if (!Array.isArray(value)) {
    return badRequest(`Malformed payload: ${field} must be an array`);
  }

  const orders = new Set<number>();
  for (let index = 0; index < value.length; index += 1) {
    const exercise = value[index];
    if (!isObject(exercise)) {
      return badRequest(
        `Malformed payload: ${field}[${index}] must be an object`
      );
    }
    if (!isNonEmptyString(exercise["externalId"])) {
      return badRequest(
        `Malformed payload: ${field}[${index}].externalId must be a non-empty string`
      );
    }
    const order = exercise["order"];
    if (!Number.isInteger(order) || (order as number) < 0) {
      return badRequest(
        `Malformed payload: ${field}[${index}].order must be a non-negative integer`
      );
    }
    if (orders.has(order as number)) {
      return badRequest(
        `Malformed payload: ${field} contains duplicate order ${String(order)}`
      );
    }
    orders.add(order as number);

    if (!isPositiveInteger(exercise["defaultSets"])) {
      return badRequest(
        `Malformed payload: ${field}[${index}].defaultSets must be a positive integer`
      );
    }
    if (!isPositiveInteger(exercise["defaultReps"])) {
      return badRequest(
        `Malformed payload: ${field}[${index}].defaultReps must be a positive integer`
      );
    }
    if (!isOptionalFiniteNumber(exercise["defaultWeight"])) {
      return badRequest(
        `Malformed payload: ${field}[${index}].defaultWeight must be a finite number`
      );
    }
    const restSeconds = exercise["defaultRestSeconds"];
    if (
      restSeconds !== undefined &&
      (!Number.isInteger(restSeconds) || (restSeconds as number) < 0)
    ) {
      return badRequest(
        `Malformed payload: ${field}[${index}].defaultRestSeconds must be a non-negative integer`
      );
    }
    if (!isOptionalString(exercise["notes"])) {
      return badRequest(
        `Malformed payload: ${field}[${index}].notes must be a string`
      );
    }
  }

  return null;
}

function validateCreateTemplate(
  payload: Record<string, unknown>
): HttpResponseInit | null {
  if (!isNonEmptyString(payload["name"])) {
    return badRequest("Malformed payload: name must be a non-empty string");
  }
  if (!isOptionalString(payload["notes"])) {
    return badRequest("Malformed payload: notes must be a string");
  }
  return validateTemplateExercises(payload["exercises"], "exercises");
}

function validateUpdateTemplate(
  payload: Record<string, unknown>
): HttpResponseInit | null {
  if (!isNonEmptyString(payload["id"])) {
    return badRequest("Malformed payload: id must be a non-empty string");
  }
  if (
    payload["name"] !== undefined &&
    !isNonEmptyString(payload["name"])
  ) {
    return badRequest("Malformed payload: name must be a non-empty string");
  }
  if (!isOptionalString(payload["notes"])) {
    return badRequest("Malformed payload: notes must be a string");
  }
  if (payload["exercises"] !== undefined) {
    return validateTemplateExercises(payload["exercises"], "exercises");
  }
  return null;
}

function validateDeleteTemplate(
  payload: Record<string, unknown>
): HttpResponseInit | null {
  if (!isNonEmptyString(payload["id"])) {
    return badRequest("Malformed payload: id must be a non-empty string");
  }
  if (!isNonEmptyString(payload["name"])) {
    return badRequest("Malformed payload: name must be a non-empty string");
  }
  return null;
}

function validateCreateCustomExercise(
  payload: Record<string, unknown>
): HttpResponseInit | null {
  if (!isNonEmptyString(payload["name"])) {
    return badRequest("Malformed payload: name must be a non-empty string");
  }
  if (!isOptionalString(payload["equipment"])) {
    return badRequest("Malformed payload: equipment must be a string");
  }
  if (!isOptionalStringArray(payload["primaryMuscles"])) {
    return badRequest("Malformed payload: primaryMuscles must be a string array");
  }
  if (!isOptionalStringArray(payload["secondaryMuscles"])) {
    return badRequest("Malformed payload: secondaryMuscles must be a string array");
  }
  if (!isOptionalStringArray(payload["instructions"])) {
    return badRequest("Malformed payload: instructions must be a string array");
  }
  if (!isOptionalString(payload["notes"])) {
    return badRequest("Malformed payload: notes must be a string");
  }
  return null;
}

/**
 * Validates the complete enqueue body before Cosmos is accessed. Top-level
 * id/requiresApproval fields are deliberately not read; the Function owns
 * the operation envelope.
 */
function validateEnqueueBody(
  body: unknown
):
  | { ok: true; value: InboxEnqueueRequest }
  | { ok: false; error: HttpResponseInit } {
  if (!isObject(body)) {
    return {
      ok: false,
      error: badRequest("Malformed body: expected a JSON object"),
    };
  }
  if (!isOperationType(body["op"])) {
    return {
      ok: false,
      error: badRequest(`Unknown op: ${JSON.stringify(body["op"])}`),
    };
  }
  if (!isObject(body["payload"])) {
    return {
      ok: false,
      error: badRequest("Malformed body: payload must be an object"),
    };
  }

  const op = body["op"];
  const payload = body["payload"];
  let validationError: HttpResponseInit | null;
  switch (op) {
    case "createTemplate":
      validationError = validateCreateTemplate(payload);
      break;
    case "updateTemplate":
      validationError = validateUpdateTemplate(payload);
      break;
    case "deleteTemplate":
      validationError = validateDeleteTemplate(payload);
      break;
    case "createCustomExercise":
      validationError = validateCreateCustomExercise(payload);
      break;
  }
  if (validationError) return { ok: false, error: validationError };

  return {
    ok: true,
    value: { op, payload } as unknown as InboxEnqueueRequest,
  };
}

function validateAckBody(
  body: unknown
):
  | { ok: true; value: InboxAckRequest }
  | { ok: false; error: HttpResponseInit } {
  if (!isObject(body) || !Array.isArray(body["results"])) {
    return {
      ok: false,
      error: badRequest("Malformed body: results must be an array"),
    };
  }

  const ids = new Set<string>();
  for (let index = 0; index < body["results"].length; index += 1) {
    const result = body["results"][index];
    if (!isObject(result)) {
      return {
        ok: false,
        error: badRequest(`Malformed body: results[${index}] must be an object`),
      };
    }
    if (!isNonEmptyString(result["id"])) {
      return {
        ok: false,
        error: badRequest(
          `Malformed body: results[${index}].id must be a non-empty string`
        ),
      };
    }
    if (ids.has(result["id"])) {
      return {
        ok: false,
        error: badRequest(`Malformed body: duplicate result id ${result["id"]}`),
      };
    }
    ids.add(result["id"]);
    if (!isAckStatus(result["status"])) {
      return {
        ok: false,
        error: badRequest(
          `Malformed body: results[${index}].status is not an ack status`
        ),
      };
    }
    if (!isOptionalString(result["error"])) {
      return {
        ok: false,
        error: badRequest(
          `Malformed body: results[${index}].error must be a string`
        ),
      };
    }
  }

  return { ok: true, value: body as unknown as InboxAckRequest };
}

function stripSystemProps(operation: InboxOperation): InboxOperation {
  const clean = { ...operation } as InboxOperation & Record<string, unknown>;
  for (const property of COSMOS_SYSTEM_PROPS) delete clean[property];
  return clean;
}

async function queryAllByStatus(
  container: Container,
  status: InboxOperationStatus
): Promise<InboxOperation[]> {
  const iterator = container.items.query(
    {
      query:
        "SELECT * FROM c WHERE c.status = @status ORDER BY c.createdAt ASC",
      parameters: [{ name: "@status", value: status }],
    },
    { maxItemCount: PAGE_SIZE }
  );
  const operations: InboxOperation[] = [];
  while (iterator.hasMoreResults()) {
    const { resources } = await iterator.fetchNext();
    for (const operation of resources ?? []) {
      operations.push(stripSystemProps(operation as InboxOperation));
    }
  }
  return operations.sort((left, right) =>
    left.createdAt.localeCompare(right.createdAt)
  );
}

function requiresApproval(op: InboxOperationType): boolean {
  return op === "updateTemplate" || op === "deleteTemplate";
}

function transitionError(
  operation: InboxOperation,
  nextStatus: InboxAckStatus
): string | null {
  if (TERMINAL_STATUSES.has(operation.status)) return null;

  if (operation.status === "pending") {
    if (operation.requiresApproval) {
      return nextStatus === "awaitingApproval" || nextStatus === "failed"
        ? null
        : `${operation.status} ${operation.op} cannot transition to ${nextStatus}`;
    }
    return nextStatus === "applied" || nextStatus === "failed"
      ? null
      : `${operation.status} ${operation.op} cannot transition to ${nextStatus}`;
  }

  if (operation.status === "awaitingApproval") {
    return nextStatus === "applied" ||
      nextStatus === "rejected" ||
      nextStatus === "failed"
      ? null
      : `${operation.status} ${operation.op} cannot transition to ${nextStatus}`;
  }

  return `Unknown current status for ${operation.id}: ${String(operation.status)}`;
}

function applyAckResult(
  operation: InboxOperation,
  result: InboxAckResult
): InboxOperation {
  const updated = stripSystemProps({ ...operation, status: result.status });
  delete updated.appliedAt;
  delete updated.error;
  if (result.status === "applied") {
    updated.appliedAt = new Date().toISOString();
  }
  if (result.status === "failed" && result.error !== undefined) {
    updated.error = result.error;
  }
  return updated;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

app.http("inboxEnqueue", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "inbox",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return badRequest("Invalid JSON body");
    }

    const validation = validateEnqueueBody(body);
    if (!validation.ok) return validation.error;

    const operation: InboxOperation = {
      id: randomUUID(),
      createdAt: new Date().toISOString(),
      op: validation.value.op,
      payload: validation.value.payload as InboxOperationPayload,
      requiresApproval: requiresApproval(validation.value.op),
      status: "pending",
    };

    try {
      await getDatabase().container(INBOX_CONTAINER).items.create(operation);
      const response: InboxEnqueueResponse = operation;
      return { jsonBody: response };
    } catch (error) {
      context.error("Inbox enqueue failed:", error);
      return { status: 500, jsonBody: { error: "Failed to enqueue operation" } };
    }
  },
});

app.http("inboxList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "inbox",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const requestedStatus = request.query.get("status") || "pending";
    if (!isOperationStatus(requestedStatus)) {
      return badRequest(`Unknown status: ${JSON.stringify(requestedStatus)}`);
    }

    try {
      const operations = await queryAllByStatus(
        getDatabase().container(INBOX_CONTAINER),
        requestedStatus
      );
      const response: InboxListResponse = { operations };
      return { jsonBody: response };
    } catch (error) {
      context.error("Inbox list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list inbox" } };
    }
  },
});

app.http("inboxAck", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "inbox/ack",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return badRequest("Invalid JSON body");
    }

    const validation = validateAckBody(body);
    if (!validation.ok) return validation.error;

    const counts: InboxAckCounts = {
      updated: 0,
      unchanged: 0,
      notFound: 0,
      invalid: 0,
    };
    const failures: string[] = [];
    const replacements: {
      operation: InboxOperation;
      result: InboxAckResult;
      invalid?: boolean;
    }[] = [];
    const container = getDatabase().container(INBOX_CONTAINER);

    // Phase one reads and validates every requested transition. No Cosmos
    // replacement occurs until all structurally valid transitions are known.
    for (const result of validation.value.results) {
      try {
        const operation = await readItemOrNull<InboxOperation>(
          container,
          result.id
        );
        if (!operation) {
          counts.notFound += 1;
          continue;
        }
        if (TERMINAL_STATUSES.has(operation.status)) {
          counts.unchanged += 1;
          continue;
        }
        const invalidTransition = transitionError(operation, result.status);
        if (invalidTransition) {
          // An ack batch arrives AFTER the phone applied these operations
          // locally. Rejecting the whole request over one bad entry would
          // leave its batch-mates `pending`, and the next sync would re-serve
          // and re-apply them — duplicate templates, the exact failure class
          // this issue exists to remove. Nor can the bad entry stay `pending`:
          // an illegal transition never becomes legal, so it would be
          // re-served forever. Force it terminal, with the reason recorded.
          replacements.push({
            operation,
            result: {
              id: result.id,
              status: "failed",
              error: `Invalid transition: ${invalidTransition}`,
            },
            invalid: true,
          });
          continue;
        }
        replacements.push({ operation, result });
      } catch (error) {
        failures.push(`read ${result.id}: ${errorMessage(error)}`);
      }
    }

    // Phase two applies every valid transition, collecting per-item failures
    // so one transient Cosmos error does not prevent independent acknowledgements.
    for (const { operation, result, invalid } of replacements) {
      const updated = applyAckResult(operation, result);
      try {
        await container.item(operation.id, operation.id).replace(updated);
        if (invalid) counts.invalid += 1;
        else counts.updated += 1;
      } catch (error) {
        failures.push(`replace ${operation.id}: ${errorMessage(error)}`);
      }
    }

    if (failures.length > 0) {
      context.error("Inbox ack incomplete:", failures);
      return {
        status: 500,
        jsonBody: {
          error: `Inbox ack incomplete: ${failures.length} operation(s) failed`,
          failures,
          counts,
        },
      };
    }

    const response: InboxAckResponse = { counts };
    return { jsonBody: response };
  },
});
