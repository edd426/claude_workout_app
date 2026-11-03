/**
 * Tests for list_medications and list_medication_logs — issue #164.
 *
 * Thin reads over GET /api/medications and GET /api/medication-doses. The one
 * rule that matters most: a dose's computedMg is reported as logged, never
 * recomputed from the medication's current concentration.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { ApiError } = await import("../src/shared/http.js");
const { listMedications, listMedicationLogs } = await import(
  "../src/tools/medications.js"
);

const vial = {
  id: "AAAAAAAA-0000-4000-8000-000000000001",
  name: "Vial A",
  doseForm: "liquid",
  vialAmountMg: 10,
  diluentMl: 2,
  allowsSyringeUnits: true,
  isArchived: false,
  createdAt: "2026-11-01T00:00:00.000Z",
  lastModified: "2026-11-01T00:00:00.000Z",
};

const dose = {
  id: "D-1",
  medicationId: vial.id,
  medicationName: "Vial A",
  takenAt: "2026-11-03T08:00:00.000Z",
  amount: 50,
  unit: "syringeUnits",
  computedMg: 2.5,
  concentrationMgPerMlAtLog: 5,
  lastModified: "2026-11-03T08:00:00.000Z",
};

beforeEach(() => {
  mockApiGet.mockReset();
});

describe("listMedications", () => {
  it("asks for active medications by default", async () => {
    mockApiGet.mockResolvedValue({ mirrored: true, medications: [vial] });

    await listMedications();

    expect(mockApiGet).toHaveBeenCalledWith("medications", {
      includeArchived: undefined,
    });
  });

  it("forwards includeArchived", async () => {
    mockApiGet.mockResolvedValue({ mirrored: true, medications: [] });

    await listMedications({ includeArchived: true });

    expect(mockApiGet).toHaveBeenCalledWith("medications", {
      includeArchived: "true",
    });
  });

  it("adds the current concentration: the direct value, else vial ÷ diluent, else null", async () => {
    mockApiGet.mockResolvedValue({
      mirrored: true,
      medications: [
        vial,
        { ...vial, id: "B", concentrationMgPerMl: 7, vialAmountMg: 10, diluentMl: 2 },
        { ...vial, id: "C", vialAmountMg: undefined, diluentMl: undefined },
        { ...vial, id: "D", diluentMl: 0 },
      ],
    });

    const result = await listMedications();

    expect(result.medications.map((m) => m.currentConcentrationMgPerMl)).toEqual([
      5,
      7,
      null,
      null,
    ]);
  });

  it("not mirrored yet is reported as such, never as 'no medications'", async () => {
    mockApiGet.mockResolvedValue({ mirrored: false, medications: [] });

    const result = await listMedications();

    expect(result.mirrored).toBe(false);
    expect(result.note).toMatch(/not been mirrored/i);
  });
});

describe("listMedicationLogs", () => {
  it("forwards medicationId and the date window", async () => {
    mockApiGet.mockResolvedValue({ mirrored: true, doses: [] });

    await listMedicationLogs({
      medicationId: vial.id,
      startDate: "2026-11-01",
      endDate: "2026-11-03",
      limit: 25,
    });

    expect(mockApiGet).toHaveBeenCalledWith("medication-doses", {
      medicationId: vial.id,
      startDate: "2026-11-01",
      endDate: "2026-11-03",
      limit: 25,
    });
  });

  it("reports each dose's stored computedMg and concentration at log time, unchanged", async () => {
    mockApiGet.mockResolvedValue({ mirrored: true, doses: [dose] });

    const result = await listMedicationLogs();

    expect(result.doses).toEqual([dose]);
  });

  it("an unknown medicationId is a clear error pointing at list_medications", async () => {
    mockApiGet.mockRejectedValue(new ApiError(404, "Functions API returned 404: Medication not found: X"));

    await expect(listMedicationLogs({ medicationId: "X" })).rejects.toThrow(
      /list_medications/
    );
  });

  it("not mirrored yet is reported as such, never as 'no doses'", async () => {
    mockApiGet.mockResolvedValue({ mirrored: false, doses: [] });

    const result = await listMedicationLogs();

    expect(result.mirrored).toBe(false);
    expect(result.note).toMatch(/not been mirrored/i);
  });
});
