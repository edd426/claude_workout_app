/**
 * GET /api/exercises/{exerciseId}/history (issue #79).
 *
 * Returns past sets for one exercise across recent workouts, most recent
 * first. The underlying Cosmos scan is hard-capped so an unbounded history
 * can never blow up the response.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { extractExerciseHistory } from "../shared/analytics";
import { parseLimit } from "../shared/readHelpers";
import { Workout } from "../shared/types";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;
// The exercise appears in only some workouts, so scan a multiple of the
// requested entry count — but never more than this hard cap.
const MAX_SCAN = 300;

app.http("exerciseHistory", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "exercises/{exerciseId}/history",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const exerciseId = request.params["exerciseId"];
    if (!exerciseId) {
      return { status: 400, jsonBody: { error: "Missing route param: exerciseId" } };
    }

    const limit = parseLimit(request, {
      defaultValue: DEFAULT_LIMIT,
      max: MAX_LIMIT,
    });
    if (!limit.ok) return limit.error;

    const scanLimit = Math.min(limit.value * 3, MAX_SCAN);

    try {
      const container = getDatabase().container("workouts");
      const { resources } = await container.items
        .query({
          query: "SELECT * FROM c ORDER BY c.startedAt DESC OFFSET 0 LIMIT @limit",
          parameters: [{ name: "@limit", value: scanLimit }],
        })
        .fetchAll();

      const entries = extractExerciseHistory(
        resources as Workout[],
        exerciseId,
        limit.value
      );

      return { jsonBody: { exerciseId, entries } };
    } catch (error) {
      context.error("Exercise history failed:", error);
      return { status: 500, jsonBody: { error: "Failed to read exercise history" } };
    }
  },
});
