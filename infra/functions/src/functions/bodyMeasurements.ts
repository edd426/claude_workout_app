/**
 * Read-only body-measurement endpoint (issue #165).
 *
 * GET /api/body-measurements?site=&startDate=&endDate=&limit=
 *   The circumference log mirrored by snapshot wire v5, newest first, plus
 *   the profile height and the most recent waist measurement (regardless of
 *   the filters) so a caller can compute the current waist-to-height ratio.
 *
 * Until a v5 push has succeeded this answers `mirrored: false` and reads no
 * v5 container: "no measurements" would be a false answer about a phone that
 * simply has not mirrored them yet. Nothing here logs measurement data.
 */

import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import { authenticate } from "../shared/auth";
import { getDatabase } from "../shared/cosmos";
import { hasV5Mirror, readSyncMeta } from "../shared/syncMeta";
import { parseIsoDateBound, parseLimit, stripSystemProps } from "../shared/readHelpers";
import { BodyMeasurement, BodyMeasurementListResponse } from "../shared/types";

const CONTAINER = "bodyMeasurements";
const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 500;

/**
 * A site is a raw string the phone owns (a newer build may add sites), so it
 * is not checked against a fixed list here — only bounded to a plain token.
 * It is passed as a query parameter either way.
 */
const SITE_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,31}$/;

function badRequest(message: string): HttpResponseInit {
  return { status: 400, jsonBody: { error: message } };
}

app.http("bodyMeasurementsList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "body-measurements",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const site = request.query.get("site") || undefined;
    if (site !== undefined && !SITE_PATTERN.test(site)) {
      return badRequest("Invalid site: expected a measurement site such as waist");
    }
    const startDate = parseIsoDateBound(request, "startDate", "start");
    if (!startDate.ok) return startDate.error;
    const endDate = parseIsoDateBound(request, "endDate", "end");
    if (!endDate.ok) return endDate.error;
    const limit = parseLimit(request, { defaultValue: DEFAULT_LIMIT, max: MAX_LIMIT });
    if (!limit.ok) return limit.error;

    try {
      const meta = await readSyncMeta();
      if (!hasV5Mirror(meta)) {
        const empty: BodyMeasurementListResponse = {
          mirrored: false,
          heightCm: null,
          measurements: [],
          latestWaist: null,
        };
        return { jsonBody: empty };
      }

      const conditions: string[] = [];
      const parameters: { name: string; value: string | number }[] = [];
      if (site !== undefined) {
        conditions.push("c.site = @site");
        parameters.push({ name: "@site", value: site });
      }
      if (startDate.value !== undefined) {
        conditions.push("c.recordedAt >= @startDate");
        parameters.push({ name: "@startDate", value: startDate.value });
      }
      if (endDate.value !== undefined) {
        conditions.push("c.recordedAt <= @endDate");
        parameters.push({ name: "@endDate", value: endDate.value });
      }
      const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")} ` : "";
      parameters.push({ name: "@limit", value: limit.value });

      const container = getDatabase().container(CONTAINER);
      const { resources } = await container.items
        .query({
          query: `SELECT * FROM c ${where}ORDER BY c.recordedAt DESC OFFSET 0 LIMIT @limit`,
          parameters,
        })
        .fetchAll();
      const { resources: latest } = await container.items
        .query({
          query:
            "SELECT TOP 1 * FROM c WHERE c.site = @site ORDER BY c.recordedAt DESC",
          parameters: [{ name: "@site", value: "waist" }],
        })
        .fetchAll();

      const latestWaist = (latest as BodyMeasurement[])[0];
      const response: BodyMeasurementListResponse = {
        mirrored: true,
        heightCm: meta?.heightCm ?? null,
        measurements: (resources as BodyMeasurement[]).map(stripSystemProps),
        latestWaist: latestWaist ? stripSystemProps(latestWaist) : null,
      };
      return { jsonBody: response };
    } catch (error) {
      // The error only: never the query results.
      context.error("Body measurement list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list body measurements" } };
    }
  },
});
