/**
 * Read-only template endpoints (issue #79).
 *
 * GET /api/templates       — list all templates (bounded)
 * GET /api/templates/{id}  — one template by id
 *
 * These back the MCP tools list_templates / get_template now that the MCP
 * server routes all data access through this API with the shared x-api-key.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { parseLimit, readItemOrNull, stripSystemProps } from "../shared/readHelpers";
import { hasV5Mirror, readSyncMeta } from "../shared/syncMeta";
import { TemplateExerciseAlternative, WorkoutTemplate } from "../shared/types";

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 200;

const ALTERNATIVES_CONTAINER = "exerciseAlternatives";

interface StoredAlternative {
  templateExerciseId?: unknown;
  externalId?: unknown;
  order?: unknown;
  note?: unknown;
}

/**
 * Issue #169: joins each template exercise's alternatives (their own mirrored
 * container, keyed by `templateExerciseId`), sorted by `order`.
 *
 * Only once a v5 push has landed: before that the key is left off — unknown —
 * rather than set to [], which would claim the slot has none. A failed read
 * degrades the same way instead of failing get_template, which the template
 * write path depends on.
 */
async function withAlternatives(
  template: WorkoutTemplate,
  context: InvocationContext
): Promise<WorkoutTemplate> {
  const exercises = Array.isArray(template.exercises) ? template.exercises : [];
  const ids = exercises.map((exercise) => exercise.id).filter((id) => typeof id === "string");
  if (ids.length === 0) return template;

  let stored: StoredAlternative[];
  try {
    if (!hasV5Mirror(await readSyncMeta())) return template;
    const { resources } = await getDatabase()
      .container(ALTERNATIVES_CONTAINER)
      .items.query({
        query: "SELECT * FROM c WHERE ARRAY_CONTAINS(@ids, c.templateExerciseId)",
        parameters: [{ name: "@ids", value: ids }],
      })
      .fetchAll();
    stored = resources as StoredAlternative[];
  } catch (error) {
    context.warn("Template alternatives read failed; serving the template without them:", error);
    return template;
  }

  const bySlot = new Map<string, TemplateExerciseAlternative[]>();
  for (const alternative of stored) {
    if (
      typeof alternative.templateExerciseId !== "string" ||
      typeof alternative.externalId !== "string" ||
      typeof alternative.order !== "number"
    ) {
      continue;
    }
    const entry: TemplateExerciseAlternative = {
      externalId: alternative.externalId,
      order: alternative.order,
    };
    if (typeof alternative.note === "string") entry.note = alternative.note;
    const list = bySlot.get(alternative.templateExerciseId) ?? [];
    list.push(entry);
    bySlot.set(alternative.templateExerciseId, list);
  }

  return {
    ...template,
    exercises: exercises.map((exercise) => ({
      ...exercise,
      alternatives: (bySlot.get(exercise.id) ?? []).sort((a, b) => a.order - b.order),
    })),
  };
}

app.http("templatesList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "templates",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const limit = parseLimit(request, {
      defaultValue: DEFAULT_LIMIT,
      max: MAX_LIMIT,
    });
    if (!limit.ok) return limit.error;

    try {
      const container = getDatabase().container("templates");
      const { resources } = await container.items
        .query({
          query: "SELECT * FROM c ORDER BY c.name OFFSET 0 LIMIT @limit",
          parameters: [{ name: "@limit", value: limit.value }],
        })
        .fetchAll();

      return { jsonBody: { templates: (resources as WorkoutTemplate[]).map(stripSystemProps) } };
    } catch (error) {
      context.error("Template list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list templates" } };
    }
  },
});

app.http("templatesGet", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "templates/{id}",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const id = request.params["id"];
    if (!id) {
      return { status: 400, jsonBody: { error: "Missing route param: id" } };
    }

    try {
      const container = getDatabase().container("templates");
      const template = await readItemOrNull<WorkoutTemplate>(container, id);
      if (!template) {
        return { status: 404, jsonBody: { error: `Template not found: ${id}` } };
      }
      return { jsonBody: await withAlternatives(stripSystemProps(template), context) };
    } catch (error) {
      context.error("Template read failed:", error);
      return { status: 500, jsonBody: { error: "Failed to read template" } };
    }
  },
});
