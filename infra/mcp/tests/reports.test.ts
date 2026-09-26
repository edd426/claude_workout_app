/**
 * Tests for the exercise-report tools — issue #135.
 * Thin wrappers over the Functions API: a read and a durable inbox write.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet, apiPost: mockApiPost };
});

const { ApiError } = await import("../src/shared/http.js");
const {
  listExerciseReports,
  resolveExerciseReport,
  getReportPhoto,
  MAX_REPORT_PHOTO_BYTES,
} = await import("../src/tools/reports.js");

const sampleReport = {
  id: "r-1",
  createdAt: "2026-08-18T10:00:00Z",
  category: "wrongExercise",
  detail: "This is really the iso-lateral press",
  exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
  exerciseName: "Barbell Bench Press",
  suggestedReplacement: "Hammer Strength Iso-Lateral Press",
  status: "open",
  lastModified: "2026-08-18T10:00:00Z",
};

beforeEach(() => {
  mockApiGet.mockReset();
  mockApiPost.mockReset();
});

describe("listExerciseReports", () => {
  it("returns the backlog and forwards every filter", async () => {
    mockApiGet.mockResolvedValue({ reports: [sampleReport] });

    const reports = await listExerciseReports({
      status: "open",
      category: "wrongExercise",
      exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
      limit: 25,
    });

    expect(reports).toEqual([sampleReport]);
    expect(mockApiGet).toHaveBeenCalledWith("reports", {
      status: "open",
      category: "wrongExercise",
      exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
      limit: 25,
    });
  });

  it("sends no status by default, letting the server pick the live backlog", async () => {
    mockApiGet.mockResolvedValue({ reports: [] });

    await listExerciseReports();

    expect(mockApiGet).toHaveBeenCalledWith("reports", {
      status: undefined,
      category: undefined,
      exerciseExternalId: undefined,
      limit: undefined,
    });
  });

  it("rejects an unknown status without calling the API", async () => {
    await expect(listExerciseReports({ status: "closed" })).rejects.toThrow(
      /Unknown report status/
    );
    expect(mockApiGet).not.toHaveBeenCalled();
  });

  it("rejects an unknown category without calling the API", async () => {
    await expect(
      listExerciseReports({ category: "featureRequest" })
    ).rejects.toThrow(/Unknown report category/);
    expect(mockApiGet).not.toHaveBeenCalled();
  });
});

describe("resolveExerciseReport", () => {
  it("enqueues an inbox operation", async () => {
    mockApiPost.mockResolvedValue({
      id: "op-1",
      op: "resolveExerciseReport",
      status: "pending",
      requiresApproval: false,
    });

    const operation = await resolveExerciseReport({
      id: "r-1",
      resolution: "Filed as #140",
    });

    expect(operation.status).toBe("pending");
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "resolveExerciseReport",
      payload: { id: "r-1", status: undefined, resolution: "Filed as #140" },
    });
  });

  it("accepts acknowledged for work that is known but not done", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    await resolveExerciseReport({ id: "r-1", status: "acknowledged" });

    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "resolveExerciseReport",
      payload: { id: "r-1", status: "acknowledged", resolution: undefined },
    });
  });

  // Reopening was refused outright until #146. The case that changed it:
  // #136's prescribed fix was acknowledged, shipped, and turned out to be
  // inert. With no way back, a real complaint had left the backlog for good.
  it("reopens a report that was closed too early", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    await resolveExerciseReport({
      id: "r-1",
      status: "open",
      resolution: "Reopened — the fix did not touch this case",
    });

    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "resolveExerciseReport",
      payload: {
        id: "r-1",
        status: "open",
        resolution: "Reopened — the fix did not touch this case",
      },
    });
  });

  it("rejects a status that is not part of the lifecycle", async () => {
    await expect(
      resolveExerciseReport({ id: "r-1", status: "wontfix" })
    ).rejects.toThrow(/status must be one of/);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  // Closing out a gym session means answering several reports at once, and
  // one call per report is three round trips plus three chances to lose track.
  it("closes several reports in one call", async () => {
    mockApiPost.mockResolvedValue({ id: "op-n" });

    const operations = await resolveExerciseReport({
      ids: ["r-1", "r-2", "r-3"],
      status: "acknowledged",
      resolution: "All three fixed in 1.4.1",
    });

    expect(Array.isArray(operations)).toBe(true);
    expect(operations).toHaveLength(3);
    expect(mockApiPost).toHaveBeenCalledTimes(3);
    expect(mockApiPost).toHaveBeenNthCalledWith(2, "inbox", {
      op: "resolveExerciseReport",
      payload: {
        id: "r-2",
        status: "acknowledged",
        resolution: "All three fixed in 1.4.1",
      },
    });
  });

  it("a single id still returns one operation, not an array", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    const result = await resolveExerciseReport({ id: "r-1" });

    expect(Array.isArray(result)).toBe(false);
  });

  it("rejects ids and id given together rather than guessing", async () => {
    await expect(
      resolveExerciseReport({ id: "r-1", ids: ["r-2"] })
    ).rejects.toThrow(/either id or ids/);
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("rejects an empty ids array", async () => {
    await expect(resolveExerciseReport({ ids: [] })).rejects.toThrow(
      /at least one/
    );
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("validates every id before enqueuing any of them", async () => {
    mockApiPost.mockResolvedValue({ id: "op-1" });

    await expect(
      resolveExerciseReport({ ids: ["r-1", ""] })
    ).rejects.toThrow(/non-empty string/);
    // Nothing enqueued: a half-applied batch is worse than a refused one.
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("requires an id", async () => {
    await expect(resolveExerciseReport({ resolution: "done" })).rejects.toThrow(
      /id must be a non-empty string/
    );
    expect(mockApiPost).not.toHaveBeenCalled();
  });
});

// ─── get_report_photo (issue #141) ────────────────────────────────────────────
// The phone uploads a report's photo to reports/{reportId}.jpg and only then
// sets photoURL to that blob *path*, which reaches the mirror by snapshot sync.

describe("getReportPhoto", () => {
  // Swift's uuidString is upper-case — this is what the mirror holds.
  const REPORT_ID = "6E4B1C2A-9D3F-4E21-8A7B-0C1D2E3F4A5B";
  const OTHER_ID = "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D";
  const PHOTO_PATH = `reports/${REPORT_ID}.jpg`;
  const SAS_URL =
    `https://teststorage.blob.core.windows.net/workout-images/${PHOTO_PATH}` +
    "?sv=2025-01-05&se=2026-09-25T07%3A00%3A00Z&sr=b&sp=r&spr=https&sig=SECRETSIG";
  // FF D8 FF is the JPEG start-of-image marker.
  const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);

  const photoReport = {
    ...sampleReport,
    id: REPORT_ID,
    category: "bug",
    detail: "Rest timer covers the Finish button",
    exerciseName: "Leg Press",
    photoURL: PHOTO_PATH,
  };

  const mockFetch = vi.fn();

  function serve(reports: unknown[]) {
    mockApiGet.mockImplementation(async (path: string) => {
      if (path === "reports") return { reports };
      if (path === "images/sas") {
        return { sasUrl: SAS_URL, expiresAt: "2026-09-25T07:00:00Z" };
      }
      throw new Error(`unexpected apiGet(${path})`);
    });
  }

  function blob(body: Uint8Array | string, init: ResponseInit = {}) {
    mockFetch.mockImplementation(async () => new Response(body, init));
  }

  function sasWasRequested(): boolean {
    return mockApiGet.mock.calls.some(([path]) => path === "images/sas");
  }

  beforeEach(() => {
    mockFetch.mockReset();
    vi.stubGlobal("fetch", mockFetch);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns the photo as base64 JPEG with a caption naming the report", async () => {
    serve([photoReport]);
    blob(JPEG, { status: 200, headers: { "content-type": "image/jpeg" } });

    const result = await getReportPhoto(REPORT_ID);

    expect(mockApiGet).toHaveBeenCalledWith(
      "reports",
      expect.objectContaining({ status: "all" })
    );
    expect(mockApiGet).toHaveBeenCalledWith("images/sas", {
      path: PHOTO_PATH,
      mode: "download",
    });
    expect(mockFetch).toHaveBeenCalledOnce();
    expect(String(mockFetch.mock.calls[0][0])).toBe(SAS_URL);
    expect(result.image).toEqual({
      data: Buffer.from(JPEG).toString("base64"),
      mimeType: "image/jpeg",
      bytes: JPEG.length,
      path: PHOTO_PATH,
    });
    expect(result.caption).toContain("Leg Press");
    expect(result.caption).toContain("bug");
    expect(result.caption).toContain("Rest timer covers the Finish button");
  });

  it("never sends the Functions API key to blob storage", async () => {
    serve([photoReport]);
    blob(JPEG);

    await getReportPhoto(REPORT_ID);

    const init = (mockFetch.mock.calls[0][1] ?? {}) as RequestInit;
    const headers = new Headers(init.headers);
    expect(headers.has("x-api-key")).toBe(false);
  });

  it("matches the report id case-insensitively", async () => {
    serve([photoReport]);
    blob(JPEG);

    const result = await getReportPhoto(REPORT_ID.toLowerCase());

    expect(result.report.id).toBe(REPORT_ID);
    expect(result.image?.path).toBe(PHOTO_PATH);
  });

  it("reports an unknown id as not found, without requesting a SAS", async () => {
    serve([photoReport]);

    await expect(getReportPhoto(OTHER_ID)).rejects.toThrow(/Report not found/);
    expect(sasWasRequested()).toBe(false);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it.each([
    ["null", null],
    ["absent", undefined],
  ])(
    "photoURL %s means no photo — or one not uploaded yet — not an error",
    async (_label, photoURL) => {
      serve([{ ...photoReport, photoURL }]);

      const result = await getReportPhoto(REPORT_ID);

      expect(result.image).toBeNull();
      expect(result.caption).toMatch(/no photo/i);
      expect(result.caption).toMatch(/not uploaded yet/i);
      expect(result.caption).toContain("Leg Press");
      expect(sasWasRequested()).toBe(false);
      expect(mockFetch).not.toHaveBeenCalled();
    }
  );

  // Mirror data is never passed straight into a SAS path request.
  it.each([
    `https://teststorage.blob.core.windows.net/workout-images/${PHOTO_PATH}`,
    `exercises/${REPORT_ID}.jpg`,
    `reports/../exercises/${REPORT_ID}.jpg`,
    `reports/${REPORT_ID}.png`,
    `/reports/${REPORT_ID}.jpg`,
    `reports/${REPORT_ID}.jpg/extra`,
    "reports/not-a-uuid.jpg",
    "",
  ])("rejects photoURL %j without requesting a SAS", async (photoURL) => {
    serve([{ ...photoReport, photoURL }]);

    await expect(getReportPhoto(REPORT_ID)).rejects.toThrow(/photoURL/);
    expect(sasWasRequested()).toBe(false);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it("rejects a photoURL that names a different report's photo", async () => {
    serve([{ ...photoReport, photoURL: `reports/${OTHER_ID}.jpg` }]);

    await expect(getReportPhoto(REPORT_ID)).rejects.toThrow(/different report/);
    expect(sasWasRequested()).toBe(false);
  });

  it("explains a blob 404 as a photo missing from storage, without leaking the SAS", async () => {
    serve([photoReport]);
    blob("", { status: 404 });

    const error = await getReportPhoto(REPORT_ID).then(
      () => null,
      (err: Error) => err
    );

    expect(error?.message).toMatch(/not in (blob )?storage/i);
    expect(error?.message).toContain(PHOTO_PATH);
    expect(error?.message).not.toContain("SECRETSIG");
  });

  it("surfaces any other blob failure with its status, without leaking the SAS", async () => {
    serve([photoReport]);
    blob("", { status: 403 });

    const error = await getReportPhoto(REPORT_ID).then(
      () => null,
      (err: Error) => err
    );

    expect(error?.message).toContain("403");
    expect(error?.message).not.toContain("SECRETSIG");
  });

  it("refuses an oversize photo from its content-length", async () => {
    serve([photoReport]);
    blob(JPEG, {
      status: 200,
      headers: { "content-length": String(MAX_REPORT_PHOTO_BYTES + 1) },
    });

    await expect(getReportPhoto(REPORT_ID)).rejects.toThrow(/too large/i);
  });

  it("refuses an oversize photo even when no content-length is sent", async () => {
    serve([photoReport]);
    const big = new Uint8Array(MAX_REPORT_PHOTO_BYTES + 1);
    big.set(JPEG);
    blob(big, { status: 200 });

    await expect(getReportPhoto(REPORT_ID)).rejects.toThrow(/too large/i);
  });

  it("keeps the cap low enough that the base64 image stays within 5 MB", () => {
    const base64Length = 4 * Math.ceil(MAX_REPORT_PHOTO_BYTES / 3);
    expect(base64Length).toBeLessThanOrEqual(5_000_000);
  });

  it("refuses a blob that is not a JPEG rather than mislabel it", async () => {
    serve([photoReport]);
    // PNG signature.
    blob(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));

    await expect(getReportPhoto(REPORT_ID)).rejects.toThrow(/not a JPEG/i);
  });

  it("explains a 400 from the SAS endpoint as a Functions app that predates #141", async () => {
    mockApiGet.mockImplementation(async (path: string) => {
      if (path === "reports") return { reports: [photoReport] };
      throw new ApiError(
        400,
        'Functions API returned 400: Invalid path: must match "exercises/{exerciseId}.jpg" ' +
          "where exerciseId is a UUID (GET /api/images/sas)"
      );
    });

    await expect(getReportPhoto(REPORT_ID)).rejects.toThrow(/redeploy/i);
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
