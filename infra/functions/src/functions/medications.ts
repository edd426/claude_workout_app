/**
 * Read-only medication endpoints (issue #164).
 *
 * GET /api/medications?includeArchived=
 *   User-defined medications, sorted by name. Archived ones are excluded
 *   unless includeArchived=true (archiving keeps history; it is not deletion).
 *
 * GET /api/medication-doses?medicationId=&startDate=&endDate=&limit=
 *   The dose log, newest first, each dose joined to its medication's name.
 *   `computedMg` and `concentrationMgPerMlAtLog` are served exactly as the
 *   phone logged them: a re-mixed vial must never rewrite past doses, so
 *   nothing here recomputes from the medication's current concentration.
 *
 * Both answer `mirrored: false`, reading no v5 container, until a v5 push has
 * succeeded. This is health data: nothing here logs a document or a query
 * result, only the error.
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
import {
  Medication,
  MedicationDose,
  MedicationDoseListResponse,
  MedicationListResponse,
} from "../shared/types";

const MEDICATIONS = "medications";
const DOSES = "medicationDoses";
const DEFAULT_DOSE_LIMIT = 100;
const MAX_DOSE_LIMIT = 500;

function badRequest(message: string): HttpResponseInit {
  return { status: 400, jsonBody: { error: message } };
}

function byName(left: Medication, right: Medication): number {
  return left.name.localeCompare(right.name, undefined, { sensitivity: "base" });
}

/**
 * Every medication, sorted by name. A handful of docs, so archived ones are
 * filtered here rather than in SQL, where `c.isArchived != true` would also
 * drop a doc that lacks the flag.
 */
async function queryMedications(includeArchived: boolean): Promise<Medication[]> {
  const { resources } = await getDatabase()
    .container(MEDICATIONS)
    .items.query({ query: "SELECT * FROM c" })
    .fetchAll();
  return (resources as Medication[])
    .filter((medication) => includeArchived || medication.isArchived !== true)
    .map(stripSystemProps)
    .sort(byName);
}

app.http("medicationsList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "medications",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const raw = request.query.get("includeArchived");
    if (raw !== null && raw !== "" && raw !== "true" && raw !== "false") {
      return badRequest('Invalid includeArchived: expected "true" or "false"');
    }
    const includeArchived = raw === "true";

    try {
      if (!hasV5Mirror(await readSyncMeta())) {
        const empty: MedicationListResponse = { mirrored: false, medications: [] };
        return { jsonBody: empty };
      }
      const response: MedicationListResponse = {
        mirrored: true,
        medications: await queryMedications(includeArchived),
      };
      return { jsonBody: response };
    } catch (error) {
      context.error("Medication list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list medications" } };
    }
  },
});

app.http("medicationDosesList", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "medication-doses",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    const medicationId = request.query.get("medicationId") || undefined;
    const startDate = parseIsoDateBound(request, "startDate", "start");
    if (!startDate.ok) return startDate.error;
    const endDate = parseIsoDateBound(request, "endDate", "end");
    if (!endDate.ok) return endDate.error;
    const limit = parseLimit(request, {
      defaultValue: DEFAULT_DOSE_LIMIT,
      max: MAX_DOSE_LIMIT,
    });
    if (!limit.ok) return limit.error;

    try {
      if (!hasV5Mirror(await readSyncMeta())) {
        const empty: MedicationDoseListResponse = { mirrored: false, doses: [] };
        return { jsonBody: empty };
      }

      // Every medication, archived included: an archived medication keeps its
      // history, and its doses still need a name.
      const medications = await queryMedications(true);
      const names = new Map(medications.map((medication) => [medication.id, medication.name]));

      const conditions: string[] = [];
      const parameters: { name: string; value: string | number }[] = [];
      if (medicationId !== undefined) {
        // The mirror holds Swift's upper-case UUIDs; a caller may not. Match
        // here, then query the stored id exactly.
        const wanted = medicationId.toLowerCase();
        const match = medications.find((medication) => medication.id.toLowerCase() === wanted);
        if (!match) {
          return {
            status: 404,
            jsonBody: { error: `Medication not found: ${medicationId}` },
          };
        }
        conditions.push("c.medicationId = @medicationId");
        parameters.push({ name: "@medicationId", value: match.id });
      }
      if (startDate.value !== undefined) {
        conditions.push("c.takenAt >= @startDate");
        parameters.push({ name: "@startDate", value: startDate.value });
      }
      if (endDate.value !== undefined) {
        conditions.push("c.takenAt <= @endDate");
        parameters.push({ name: "@endDate", value: endDate.value });
      }
      const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")} ` : "";
      parameters.push({ name: "@limit", value: limit.value });

      const { resources } = await getDatabase()
        .container(DOSES)
        .items.query({
          query: `SELECT * FROM c ${where}ORDER BY c.takenAt DESC OFFSET 0 LIMIT @limit`,
          parameters,
        })
        .fetchAll();

      const response: MedicationDoseListResponse = {
        mirrored: true,
        doses: (resources as MedicationDose[]).map((dose) => ({
          ...stripSystemProps(dose),
          medicationName:
            dose.medicationId !== undefined ? names.get(dose.medicationId) ?? null : null,
        })),
      };
      return { jsonBody: response };
    } catch (error) {
      context.error("Medication dose list failed:", error);
      return { status: 500, jsonBody: { error: "Failed to list medication doses" } };
    }
  },
});
