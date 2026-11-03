/**
 * Tests for list_body_measurements — issue #165.
 *
 * A thin read over GET /api/body-measurements, plus the one derived value the
 * mirror does not store: the current waist-to-height ratio and its NICE NG246
 * band (< 0.5 healthy, 0.5–0.59 increased, ≥ 0.6 high).
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { listBodyMeasurements, waistToHeightBand, waistToHeightRatio } = await import(
  "../src/tools/bodyMeasurements.js"
);

const waist = {
  id: "M-1",
  site: "waist",
  valueCm: 86.5,
  recordedAt: "2026-11-03T07:00:00.000Z",
  note: "navel, morning",
  lastModified: "2026-11-03T07:00:00.000Z",
};

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("waist-to-height ratio", () => {
  it("is waist ÷ height", () => {
    expect(waistToHeightRatio(86.5, 182.88)).toBeCloseTo(0.47299, 5);
  });

  it.each([
    [undefined, 180],
    [80, undefined],
    [0, 180],
    [80, 0],
    [-80, 180],
    [Number.NaN, 180],
  ])("is null without a usable waist (%s) or height (%s)", (waistCm, heightCm) => {
    expect(waistToHeightRatio(waistCm, heightCm)).toBeNull();
  });

  it.each([
    [0.4999, "healthy"],
    [0.5, "increased"],
    [0.5999, "increased"],
    [0.6, "high"],
    [0.3, "healthy"],
    [0.75, "high"],
  ])("NICE NG246 band for %s is %s", (ratio, band) => {
    expect(waistToHeightBand(ratio)).toBe(band);
  });

  it("a ratio that is 0.6 up to floating-point noise is still high (same rule as the phone)", () => {
    // 39.3 in ÷ 65.5 in is exactly 0.6, but through cm it computes as
    // 0.5999999999999999. The phone rounds to 6 places before banding.
    const ratio = waistToHeightRatio(39.3 * 2.54, 65.5 * 2.54);
    expect(ratio).not.toBe(0.6);
    expect(waistToHeightBand(ratio as number)).toBe("high");
  });
});

describe("listBodyMeasurements", () => {
  it("forwards every filter to GET body-measurements", async () => {
    mockApiGet.mockResolvedValue({
      mirrored: true,
      heightCm: 182.88,
      measurements: [],
      latestWaist: null,
    });

    await listBodyMeasurements({
      site: "waist",
      startDate: "2026-10-01",
      endDate: "2026-11-03",
      limit: 10,
    });

    expect(mockApiGet).toHaveBeenCalledWith("body-measurements", {
      site: "waist",
      startDate: "2026-10-01",
      endDate: "2026-11-03",
      limit: 10,
    });
  });

  it("returns the height, the latest waist-to-height ratio with its band, and the log", async () => {
    mockApiGet.mockResolvedValue({
      mirrored: true,
      heightCm: 182.88,
      measurements: [waist],
      latestWaist: waist,
    });

    const result = await listBodyMeasurements();

    expect(result.heightCm).toBe(182.88);
    expect(result.measurements).toEqual([waist]);
    expect(result.waistToHeight).toEqual({
      ratio: 0.473,
      band: "healthy",
      bandDescription: expect.stringContaining("below 0.5"),
      guideline: "NICE NG246",
      waistCm: 86.5,
      measuredAt: "2026-11-03T07:00:00.000Z",
    });
    expect(result.note).toBeUndefined();
  });

  it("an increased-risk waist reads as increased", async () => {
    const wide = { ...waist, valueCm: 100 };
    mockApiGet.mockResolvedValue({
      mirrored: true,
      heightCm: 180,
      measurements: [wide],
      latestWaist: wide,
    });

    const result = await listBodyMeasurements();

    expect(result.waistToHeight?.band).toBe("increased");
    expect(result.waistToHeight?.ratio).toBe(0.556);
  });

  it("without a height there is no ratio, and the note says why", async () => {
    mockApiGet.mockResolvedValue({
      mirrored: true,
      heightCm: null,
      measurements: [waist],
      latestWaist: waist,
    });

    const result = await listBodyMeasurements();

    expect(result.waistToHeight).toBeNull();
    expect(result.note).toMatch(/height/i);
  });

  it("without a waist measurement there is no ratio, and the note says why", async () => {
    mockApiGet.mockResolvedValue({
      mirrored: true,
      heightCm: 182.88,
      measurements: [],
      latestWaist: null,
    });

    const result = await listBodyMeasurements();

    expect(result.waistToHeight).toBeNull();
    expect(result.note).toMatch(/waist/i);
  });

  it("not mirrored yet is reported as such, never as 'no measurements'", async () => {
    mockApiGet.mockResolvedValue({
      mirrored: false,
      heightCm: null,
      measurements: [],
      latestWaist: null,
    });

    const result = await listBodyMeasurements();

    expect(result.mirrored).toBe(false);
    expect(result.waistToHeight).toBeNull();
    expect(result.note).toMatch(/not been mirrored/i);
    expect(result.note).toMatch(/not mean there are none/i);
  });

  it("rejects an unknown site without calling the API", async () => {
    await expect(listBodyMeasurements({ site: "neck" })).rejects.toThrow(
      /Unknown measurement site/
    );
    expect(mockApiGet).not.toHaveBeenCalled();
  });
});
