/**
 * Read-only workout endpoints (issue #79).
 *
 * GET /api/workouts       — list workout summaries, optional date filtering,
 *                           bounded by a capped limit param
 * GET /api/workouts/{id}  — full workout detail
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { toSummary } from "../shared/analytics";
import { parseIsoDate, parseLimit, readItemOrNull } from "../shared/readHelpers";
import { Workout } from "../shared/types";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

app.http("workoutsList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "workouts",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const startDate = parseIsoDate(request, "startDate");
    if (!startDate.ok) return startDate.error;
    const endDate = parseIsoDate(request, "endDate");
    if (!endDate.ok) return endDate.error;
    const limit = parseLimit(request, {
      defaultValue: DEFAULT_LIMIT,
      max: MAX_LIMIT,
    });
    if (!limit.ok) return limit.error;

    const conditions: string[] = [];
    const parameters: { name: string; value: string | number }[] = [];
    if (startDate.value) {
      conditions.push("c.startedAt >= @startDate");
      parameters.push({ name: "@startDate", value: startDate.value });
    }
    if (endDate.value) {
      conditions.push("c.startedAt <= @endDate");
      parameters.push({ name: "@endDate", value: endDate.value });
    }
    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    parameters.push({ name: "@limit", value: limit.value });

    try {
      const container = getDatabase().container("workouts");
      const { resources } = await container.items
        .query({
          query: `SELECT * FROM c ${where} ORDER BY c.startedAt DESC OFFSET 0 LIMIT @limit`,
          parameters,
        })
        .fetchAll();

      return { jsonBody: { workouts: (resources as Workout[]).map(toSummary) } };
    } catch (error) {
      context.error("Workout list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list workouts" } };
    }
  },
});

app.http("workoutsGet", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "workouts/{id}",
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
      const container = getDatabase().container("workouts");
      const workout = await readItemOrNull<Workout>(container, id);
      if (!workout) {
        return { status: 404, jsonBody: { error: `Workout not found: ${id}` } };
      }
      return { jsonBody: workout };
    } catch (error) {
      context.error("Workout read failed:", error);
      return { status: 500, jsonBody: { error: "Failed to read workout" } };
    }
  },
});
