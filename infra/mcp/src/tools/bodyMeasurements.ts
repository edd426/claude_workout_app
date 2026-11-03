/**
 * Body-measurement read tool (issue #165).
 *
 * `list_body_measurements` reads the circumference log mirrored by snapshot
 * wire v5 (GET /api/body-measurements) and adds the one value the mirror does
 * not store: the current waist-to-height ratio, banded per NICE NG246.
 *
 * The band rule matches the phone's `BodyMetrics.band` exactly (rounded to 6
 * decimal places first), so this tool and the app never disagree about a
 * measurement that sits on a boundary.
 */

import { apiGet } from "../shared/http.js";

export const MEASUREMENT_SITES: readonly string[] = [
  "waist",
  "hips",
  "chest",
  "arm",
  "thigh",
  "calf",
];

export interface BodyMeasurement {
  id: string;
  site: string;
  valueCm: number;
  recordedAt: string;
  note?: string;
  lastModified: string;
}

interface BodyMeasurementListResponse {
  mirrored: boolean;
  heightCm: number | null;
  measurements: BodyMeasurement[];
  latestWaist: BodyMeasurement | null;
}

export type WaistToHeightBand = "healthy" | "increased" | "high";

const BAND_DESCRIPTIONS: Record<WaistToHeightBand, string> = {
  healthy: "below 0.5: healthy, no increased health risk",
  increased: "0.5 to 0.59: increased health risk",
  high: "0.6 or more: high health risk",
};

export interface WaistToHeight {
  /** Rounded to 3 decimal places for display; the band uses full precision. */
  ratio: number;
  band: WaistToHeightBand;
  bandDescription: string;
  guideline: "NICE NG246";
  waistCm: number;
  measuredAt: string;
}

export interface BodyMeasurementsResult {
  /** False until the phone has pushed its v5 data at least once. */
  mirrored: boolean;
  heightCm: number | null;
  /** From the latest waist measurement, whatever the list's filters. */
  waistToHeight: WaistToHeight | null;
  measurements: BodyMeasurement[];
  note?: string;
}

function positive(value: number | null | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : null;
}

/** waist ÷ height, or null unless both are positive finite numbers. */
export function waistToHeightRatio(
  waistCm: number | null | undefined,
  heightCm: number | null | undefined
): number | null {
  const waist = positive(waistCm);
  const height = positive(heightCm);
  return waist === null || height === null ? null : waist / height;
}

/**
 * NICE NG246: < 0.5 healthy, 0.5–0.59 increased, ≥ 0.6 high. Rounded to 6
 * places first: 39.3 in ÷ 65.5 in is exactly 0.6 but computes through cm as
 * 0.5999999999999999, and that noise must not move anyone down a band.
 */
export function waistToHeightBand(ratio: number): WaistToHeightBand {
  const rounded = Math.round(ratio * 1_000_000) / 1_000_000;
  if (rounded < 0.5) return "healthy";
  if (rounded < 0.6) return "increased";
  return "high";
}

export async function listBodyMeasurements(
  options: {
    site?: string;
    startDate?: string;
    endDate?: string;
    limit?: number;
  } = {}
): Promise<BodyMeasurementsResult> {
  if (options.site !== undefined && !MEASUREMENT_SITES.includes(options.site)) {
    throw new Error(
      `Unknown measurement site: ${options.site}. ` +
        `Expected one of ${MEASUREMENT_SITES.join(", ")}.`
    );
  }

  const response = await apiGet<BodyMeasurementListResponse>("body-measurements", {
    site: options.site,
    startDate: options.startDate,
    endDate: options.endDate,
    limit: options.limit,
  });

  const result: BodyMeasurementsResult = {
    mirrored: response.mirrored,
    heightCm: response.heightCm,
    waistToHeight: null,
    measurements: response.measurements,
  };

  if (!response.mirrored) {
    result.note =
      "Body measurements have not been mirrored yet: they reach the cloud " +
      "from ClaudeLifter 1.9.0, after the phone's first sync on that build. " +
      "This does not mean there are none.";
    return result;
  }

  const waist = response.latestWaist;
  const ratio = waistToHeightRatio(waist?.valueCm, response.heightCm);
  if (waist && ratio !== null) {
    const band = waistToHeightBand(ratio);
    result.waistToHeight = {
      ratio: Math.round(ratio * 1000) / 1000,
      band,
      bandDescription: BAND_DESCRIPTIONS[band],
      guideline: "NICE NG246",
      waistCm: waist.valueCm,
      measuredAt: waist.recordedAt,
    };
  } else if (positive(response.heightCm) === null) {
    result.note =
      "No height is set in the app (Settings → height), so there is no " +
      "waist-to-height ratio.";
  } else {
    result.note =
      "No waist measurement has been logged, so there is no waist-to-height ratio.";
  }
  return result;
}
