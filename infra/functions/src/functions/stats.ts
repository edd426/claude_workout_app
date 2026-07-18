/**
 * Stats + calendar read endpoints (issue #79).
 *
 * GET /api/stats     — summary statistics (totals, PRs, frequency). The scan
 *                      over workouts is hard-capped at the most recent 500.
 * GET /api/calendar  — per-day workout frequency for a required date range.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { buildCalendar, computeStats } from "../shared/analytics";
import { parseIsoDate } from "../shared/readHelpers";
import { Workout } from "../shared/types";

const STATS_MAX_SCAN = 500;
const CALENDAR_MAX_SCAN = 1000;

app.http("stats", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "stats",
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
    parameters.push({ name: "@limit", value: STATS_MAX_SCAN });

    try {
      const container = getDatabase().container("workouts");
      const { resources } = await container.items
        .query({
          query: `SELECT * FROM c ${where} ORDER BY c.startedAt DESC OFFSET 0 LIMIT @limit`,
          parameters,
        })
        .fetchAll();

      return { jsonBody: computeStats(resources as Workout[]) };
    } catch (error) {
      context.error("Stats failed:", error);
      return { status: 500, jsonBody: { error: "Failed to compute stats" } };
    }
  },
});

app.http("calendar", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "calendar",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const startDate = parseIsoDate(request, "startDate", { required: true });
    if (!startDate.ok) return startDate.error;
    const endDate = parseIsoDate(request, "endDate", { required: true });
    if (!endDate.ok) return endDate.error;

    try {
      const container = getDatabase().container("workouts");
      const { resources } = await container.items
        .query({
          query:
            "SELECT * FROM c WHERE c.startedAt >= @startDate AND c.startedAt <= @endDate " +
            "ORDER BY c.startedAt OFFSET 0 LIMIT @limit",
          parameters: [
            { name: "@startDate", value: startDate.value as string },
            { name: "@endDate", value: endDate.value as string },
            { name: "@limit", value: CALENDAR_MAX_SCAN },
          ],
        })
        .fetchAll();

      return { jsonBody: { days: buildCalendar(resources as Workout[]) } };
    } catch (error) {
      context.error("Calendar failed:", error);
      return { status: 500, jsonBody: { error: "Failed to build calendar" } };
    }
  },
});
