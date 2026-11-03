/**
 * Medication read tools (issue #164). Read-only by design: the issue rules out
 * MCP writes for the medication log.
 *
 * `list_medications` reads GET /api/medications; `list_medication_logs` reads
 * GET /api/medication-doses, which joins each dose to its medication's name.
 *
 * A dose's `computedMg`, `concentrationMgPerMlAtLog` and
 * `tabletStrengthMgAtLog` are passed through exactly as the phone logged
 * them. A vial re-mixed later, or a new tablet strength, must not rewrite the
 * past, so nothing here recomputes a dose from a medication's current values.
 * This is health data: nothing here logs it.
 */

import { ApiError, apiGet } from "../shared/http.js";

export interface Medication {
  id: string;
  name: string;
  doseForm: string;
  massUnit?: string;
  tabletStrengthMg?: number;
  concentrationMgPerMl?: number;
  vialAmountMg?: number;
  diluentMl?: number;
  allowsSyringeUnits: boolean;
  isArchived: boolean;
  createdAt: string;
  lastModified: string;
}

export interface MedicationWithConcentration extends Medication {
  /**
   * The medication's concentration TODAY: the direct value if set, otherwise
   * vial mg ÷ diluent mL, otherwise null. Not the concentration of any past
   * dose — each dose carries its own `concentrationMgPerMlAtLog`.
   */
  currentConcentrationMgPerMl: number | null;
}

export interface MedicationDose {
  id: string;
  medicationId?: string;
  medicationName: string | null;
  takenAt: string;
  amount: number;
  unit: string;
  computedMg?: number;
  concentrationMgPerMlAtLog?: number;
  /** Tablet doses: the strength on file when the dose was logged. */
  tabletStrengthMgAtLog?: number;
  note?: string;
  lastModified: string;
}

export interface MedicationsResult {
  mirrored: boolean;
  medications: MedicationWithConcentration[];
  note?: string;
}

export interface MedicationLogsResult {
  mirrored: boolean;
  doses: MedicationDose[];
  note?: string;
}

const NOT_MIRRORED =
  "Medications have not been mirrored yet: they reach the cloud from " +
  "ClaudeLifter 1.9.0, after the phone's first sync on that build. This " +
  "does not mean there are none.";

function positive(value: number | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : null;
}

/** Same rule as the phone: the direct value wins, else vial ÷ diluent. */
export function currentConcentration(medication: Medication): number | null {
  const direct = positive(medication.concentrationMgPerMl);
  if (direct !== null) return direct;
  const vial = positive(medication.vialAmountMg);
  const diluent = positive(medication.diluentMl);
  return vial !== null && diluent !== null ? vial / diluent : null;
}

export async function listMedications(
  options: { includeArchived?: boolean } = {}
): Promise<MedicationsResult> {
  const response = await apiGet<{ mirrored: boolean; medications: Medication[] }>(
    "medications",
    { includeArchived: options.includeArchived === true ? "true" : undefined }
  );
  const result: MedicationsResult = {
    mirrored: response.mirrored,
    medications: response.medications.map((medication) => ({
      ...medication,
      currentConcentrationMgPerMl: currentConcentration(medication),
    })),
  };
  if (!response.mirrored) result.note = NOT_MIRRORED;
  return result;
}

export async function listMedicationLogs(
  options: {
    medicationId?: string;
    startDate?: string;
    endDate?: string;
    limit?: number;
  } = {}
): Promise<MedicationLogsResult> {
  let response: { mirrored: boolean; doses: MedicationDose[] };
  try {
    response = await apiGet("medication-doses", {
      medicationId: options.medicationId,
      startDate: options.startDate,
      endDate: options.endDate,
      limit: options.limit,
    });
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) {
      throw new Error(
        `${err.message}. Call list_medications (with includeArchived: true ` +
          "for archived ones) and use an id from its results."
      );
    }
    throw err;
  }
  const result: MedicationLogsResult = {
    mirrored: response.mirrored,
    doses: response.doses,
  };
  if (!response.mirrored) result.note = NOT_MIRRORED;
  return result;
}
