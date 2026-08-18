/**
 * Read-only exercise-report endpoint (issue #135).
 *
 * GET /api/reports — the complaint backlog the phone has filed, filterable by
 *   status, category, and exercise. Defaults to everything not yet resolved,
 *   because that is the question worth asking almost every time.
 *
 * Reports reach Cosmos through snapshot sync like any other phone-owned
 * collection; nothing writes them here. They are closed out through the inbox
 * (`resolveExerciseReport`), which the phone drains — a direct write to the
 * mirror would be erased by the next snapshot push.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { parseLimit } from "../shared/readHelpers";
import { ExerciseReport, ExerciseReportListResponse } from "../shared/types";

const CONTAINER = "exerciseReports";
const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 500;

const STATUSES = ["open", "acknowledged", "resolved"];

function badRequest(message: string): HttpResponseInit {
  return { status: 400, jsonBody: { error: message } };
}

app.http("reportsList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "reports",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const status = request.query.get("status") ?? undefined;
    if (status !== undefined && status !== "all" && !STATUSES.includes(status)) {
      return badRequest(
        `Unknown status: ${status}. Expected one of ${STATUSES.join(", ")}, or "all".`
      );
    }
    const category = request.query.get("category") ?? undefined;
    const exerciseExternalId =
      request.query.get("exerciseExternalId") ?? undefined;
    const limit = parseLimit(request, {
      defaultValue: DEFAULT_LIMIT,
      max: MAX_LIMIT,
    });
    if (!limit.ok) return limit.error;

    const conditions: string[] = [];
    const parameters: { name: string; value: string | number }[] = [];

    if (status === undefined) {
      // The useful default: acknowledged reports are still outstanding work,
      // so "not resolved" is the backlog — not "status = open".
      conditions.push("c.status != @resolved");
      parameters.push({ name: "@resolved", value: "resolved" });
    } else if (status !== "all") {
      conditions.push("c.status = @status");
      parameters.push({ name: "@status", value: status });
    }
    if (category !== undefined) {
      conditions.push("c.category = @category");
      parameters.push({ name: "@category", value: category });
    }
    if (exerciseExternalId !== undefined) {
      conditions.push("c.exerciseExternalId = @exerciseExternalId");
      parameters.push({
        name: "@exerciseExternalId",
        value: exerciseExternalId,
      });
    }
    const where =
      conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    parameters.push({ name: "@limit", value: limit.value });

    try {
      const { resources } = await getDatabase()
        .container(CONTAINER)
        .items.query({
          query:
            `SELECT * FROM c ${where} ORDER BY c.createdAt DESC ` +
            `OFFSET 0 LIMIT @limit`,
          parameters,
        })
        .fetchAll();

      const response: ExerciseReportListResponse = {
        reports: resources as ExerciseReport[],
      };
      return { jsonBody: response };
    } catch (error) {
      context.error("Report list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list reports" } };
    }
  },
});
