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
import { parseLimit, readItemOrNull } from "../shared/readHelpers";
import { WorkoutTemplate } from "../shared/types";

const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 200;

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

      return { jsonBody: { templates: resources as WorkoutTemplate[] } };
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
      return { jsonBody: template };
    } catch (error) {
      context.error("Template read failed:", error);
      return { status: 500, jsonBody: { error: "Failed to read template" } };
    }
  },
});
