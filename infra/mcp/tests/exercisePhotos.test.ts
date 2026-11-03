/**
 * Tests for attach_exercise_photo — issue #170.
 *
 * Order of operations, each step refused before the next on failure:
 *   1. externalId has the exact photo-path grammar (no network yet)
 *   2. the image is base64 of a JPEG of at most 3.75 MB (no network yet)
 *   3. the exercise exists (catalog, or a synced/queued custom exercise)
 *   4. a WRITE SAS from GET /api/images/sas for exercises/ext/{externalId}.jpg
 *   5. PUT straight to blob storage, never carrying the API key
 *   6. enqueue setExercisePhoto { externalId, blobPath } (approval on the phone)
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet, apiPost: mockApiPost };
});

const { ApiError } = await import("../src/shared/http.js");
const { attachExercisePhoto, MAX_EXERCISE_PHOTO_BYTES } = await import(
  "../src/tools/exercisePhotos.js"
);
const { isPhotoExternalId } = await import("../src/shared/exercisePhotoPath.js");
const { handleToolCall, TOOLS } = await import("../src/registry.js");

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0xff, 0xd9]);
const JPEG_B64 = JPEG.toString("base64");
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CUSTOM = "custom:belt-squat:10000000-0000-4000-8000-000000000008";
const STORAGE = "https://teststorage.blob.core.windows.net/workout-images";

const mockFetch = vi.fn();

function sasFor(path: string) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  return { sasUrl: `${STORAGE}/${encoded}?sv=2024&sp=cw&sig=SECRET`, expiresAt: "x" };
}

function serve(options: { customExercises?: unknown[] } = {}) {
  mockApiGet.mockImplementation(async (path: string, params?: Record<string, string>) => {
    if (path === "images/sas") return sasFor(params?.path ?? "");
    if (path === "sync/snapshot") {
      return { snapshot: { customExercises: options.customExercises ?? [] } };
    }
    if (path === "inbox") return { operations: [] };
    throw new Error(`unexpected apiGet(${path})`);
  });
}

beforeEach(() => {
  mockApiGet.mockReset();
  mockApiPost.mockReset();
  mockApiPost.mockImplementation(async (_path: string, body: { op: string; payload: unknown }) => ({
    id: "op-1",
    createdAt: "2026-11-03T10:00:00.000Z",
    op: body.op,
    payload: body.payload,
    requiresApproval: true,
    status: "pending",
  }));
  mockFetch.mockReset();
  mockFetch.mockImplementation(async () => new Response(null, { status: 201 }));
  vi.stubGlobal("fetch", mockFetch);
  serve();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

function noNetwork() {
  expect(mockApiGet).not.toHaveBeenCalled();
  expect(mockApiPost).not.toHaveBeenCalled();
  expect(mockFetch).not.toHaveBeenCalled();
}

describe("attachExercisePhoto — happy path", () => {
  it("uploads with a write SAS, then enqueues setExercisePhoto", async () => {
    const result = await attachExercisePhoto({
      externalId: "Leg_Extensions",
      imageBase64: JPEG_B64,
    });

    expect(mockApiGet).toHaveBeenCalledWith("images/sas", {
      path: "exercises/ext/Leg_Extensions.jpg",
      mode: "upload",
    });

    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(sasFor("exercises/ext/Leg_Extensions.jpg").sasUrl);
    expect(init.method).toBe("PUT");
    const headers = new Headers(init.headers);
    expect(headers.get("x-ms-blob-type")).toBe("BlockBlob");
    expect(headers.get("content-type")).toBe("image/jpeg");
    // Storage gets the SAS, never the Functions API key.
    expect(headers.get("x-api-key")).toBeNull();
    expect(Buffer.from(init.body as Uint8Array)).toEqual(JPEG);

    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "setExercisePhoto",
      payload: {
        externalId: "Leg_Extensions",
        blobPath: "exercises/ext/Leg_Extensions.jpg",
      },
    });

    expect(result.operation.id).toBe("op-1");
    expect(result.exercise).toEqual({ externalId: "Leg_Extensions", name: "Leg Extensions" });
    expect(result.blobPath).toBe("exercises/ext/Leg_Extensions.jpg");
    expect(result.bytes).toBe(JPEG.length);
    expect(result.note).toMatch(/approv/i);
  });

  it("uploads before it enqueues, so an op never points at a missing blob", async () => {
    const order: string[] = [];
    mockFetch.mockImplementation(async () => {
      order.push("upload");
      return new Response(null, { status: 201 });
    });
    mockApiPost.mockImplementation(async () => {
      order.push("enqueue");
      return { id: "op-1" };
    });

    await attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: JPEG_B64 });

    expect(order).toEqual(["upload", "enqueue"]);
  });

  it("accepts a synced custom exercise; its path keeps the colons", async () => {
    serve({
      customExercises: [
        {
          id: "10000000-0000-4000-8000-000000000008",
          externalId: CUSTOM,
          name: "Belt Squat",
          primaryMuscles: ["quadriceps"],
        },
      ],
    });

    const result = await attachExercisePhoto({ externalId: CUSTOM, imageBase64: JPEG_B64 });

    expect(mockApiGet).toHaveBeenCalledWith("images/sas", {
      path: `exercises/ext/${CUSTOM}.jpg`,
      mode: "upload",
    });
    expect(result.exercise.name).toBe("Belt Squat");
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "setExercisePhoto",
      payload: { externalId: CUSTOM, blobPath: `exercises/ext/${CUSTOM}.jpg` },
    });
  });

  it("accepts a data:image/jpeg;base64 URL and line-wrapped base64", async () => {
    const wrapped = `data:image/jpeg;base64,${JPEG_B64.slice(0, 8)}\n${JPEG_B64.slice(8)}\n`;

    await attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: wrapped });

    const [, init] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(Buffer.from(init.body as Uint8Array)).toEqual(JPEG);
  });

  it("accepts a photo of exactly the size limit", async () => {
    const big = Buffer.alloc(MAX_EXERCISE_PHOTO_BYTES);
    JPEG.copy(big);

    const result = await attachExercisePhoto({
      externalId: "Leg_Extensions",
      imageBase64: big.toString("base64"),
    });

    expect(result.bytes).toBe(MAX_EXERCISE_PHOTO_BYTES);
  });
});

describe("attachExercisePhoto — refused before any request", () => {
  it.each([
    ["../reports/x"],
    ["Leg/Press"],
    ["Leg Press"],
    ["Leg.Press"],
    ["Leg%2FPress"],
    ["_Leading"],
    [""],
    ["custom:Belt-Squat:10000000-0000-4000-8000-000000000008"],
    ["custom:belt-squat:10000000-0000-4000-8000-00000000000A"],
  ])("an externalId of %j", async (externalId) => {
    await expect(
      attachExercisePhoto({ externalId, imageBase64: JPEG_B64 })
    ).rejects.toThrow(/externalId/);
    noNetwork();
  });

  it("an image that is not a JPEG", async () => {
    await expect(
      attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: PNG.toString("base64") })
    ).rejects.toThrow(/not a JPEG/);
    noNetwork();
  });

  it("a data URL for another image type", async () => {
    await expect(
      attachExercisePhoto({
        externalId: "Leg_Extensions",
        imageBase64: `data:image/png;base64,${JPEG_B64}`,
      })
    ).rejects.toThrow(/JPEG/);
    noNetwork();
  });

  it("an image one byte over 3.75 MB", async () => {
    const big = Buffer.alloc(MAX_EXERCISE_PHOTO_BYTES + 1);
    JPEG.copy(big);

    await expect(
      attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: big.toString("base64") })
    ).rejects.toThrow(/too large/);
    noNetwork();
  });

  it.each([["not base64!"], ["@@@@"], ["A"], [""]])(
    "imageBase64 of %j",
    async (imageBase64) => {
      await expect(
        attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64 })
      ).rejects.toThrow(/imageBase64/);
      noNetwork();
    }
  );

  it("a missing imageBase64", async () => {
    await expect(attachExercisePhoto({ externalId: "Leg_Extensions" })).rejects.toThrow(
      /imageBase64/
    );
    noNetwork();
  });
});

describe("attachExercisePhoto — refused after a lookup", () => {
  it("an exercise that is not in the catalog, with suggestions, before any SAS", async () => {
    await expect(
      attachExercisePhoto({ externalId: "Leg_Extension_Machine_9000", imageBase64: JPEG_B64 })
    ).rejects.toThrow(/Unknown externalId "Leg_Extension_Machine_9000".*Suggestions/);
    expect(mockApiGet).not.toHaveBeenCalledWith("images/sas", expect.anything());
    expect(mockFetch).not.toHaveBeenCalled();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("a SAS URL for some other blob is refused without uploading", async () => {
    mockApiGet.mockImplementation(async () => sasFor("exercises/ext/Leg_Press.jpg"));

    await expect(
      attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: JPEG_B64 })
    ).rejects.toThrow(/different blob/);
    expect(mockFetch).not.toHaveBeenCalled();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("a 400 from the SAS endpoint says the Functions app predates #170", async () => {
    mockApiGet.mockImplementation(async () => {
      throw new ApiError(400, "Functions API returned 400: Invalid path");
    });

    await expect(
      attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: JPEG_B64 })
    ).rejects.toThrow(/#170.*redeploy/);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it("a failed upload names the blob, never the SAS URL, and enqueues nothing", async () => {
    mockFetch.mockImplementation(async () => new Response("denied", { status: 403 }));

    const error = await attachExercisePhoto({
      externalId: "Leg_Extensions",
      imageBase64: JPEG_B64,
    }).catch((err: Error) => err);

    expect(error).toBeInstanceOf(Error);
    expect((error as Error).message).toContain("exercises/ext/Leg_Extensions.jpg");
    expect((error as Error).message).toContain("403");
    expect((error as Error).message).not.toContain("SECRET");
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("a network failure during upload never echoes the SAS URL", async () => {
    mockFetch.mockImplementation(async () => {
      throw new TypeError(`fetch failed for ${STORAGE}/x?sig=SECRET`);
    });

    const error = await attachExercisePhoto({
      externalId: "Leg_Extensions",
      imageBase64: JPEG_B64,
    }).catch((err: Error) => err);

    expect((error as Error).message).toContain("Cannot upload");
    expect((error as Error).message).not.toContain("SECRET");
  });

  it("an enqueue refused by an older Functions app says the photo is uploaded but not queued", async () => {
    mockApiPost.mockImplementation(async () => {
      throw new ApiError(400, 'Functions API returned 400: Unknown op: "setExercisePhoto"');
    });

    await expect(
      attachExercisePhoto({ externalId: "Leg_Extensions", imageBase64: JPEG_B64 })
    ).rejects.toThrow(/uploaded.*not queued/);
  });
});

describe("photo externalId grammar (same as the Functions allow-list)", () => {
  it.each([
    ["Leg_Extensions", true],
    ["Barbell_Bench_Press_-_Medium_Grip", true],
    ["3_4_Sit-Up", true],
    [CUSTOM, true],
    [`custom:${"a".repeat(64)}:10000000-0000-4000-8000-000000000008`, true],
    [`custom:${"a".repeat(65)}:10000000-0000-4000-8000-000000000008`, false],
    ["custom::10000000-0000-4000-8000-000000000008", false],
    ["custom:belt_squat:10000000-0000-4000-8000-000000000008", false],
    [`${CUSTOM}:x`, false],
    ["Leg:Press", false],
    ["..", false],
    ["a".repeat(129), false],
    ["Lég_Press", false],
    ["Leg\\Press", false],
  ])("%j → %s", (externalId, ok) => {
    expect(isPhotoExternalId(externalId)).toBe(ok);
  });
});

describe("attach_exercise_photo registration", () => {
  it("is listed with externalId and imageBase64 required", () => {
    const tool = TOOLS.find((candidate) => candidate.name === "attach_exercise_photo");
    expect(tool).toBeDefined();
    expect(tool?.inputSchema).toEqual(
      expect.objectContaining({ required: ["externalId", "imageBase64"] })
    );
    expect(tool?.description).toMatch(/approv/i);
  });

  it("dispatches and returns the queued operation as JSON", async () => {
    const result = await handleToolCall("attach_exercise_photo", {
      externalId: "Leg_Extensions",
      imageBase64: JPEG_B64,
    });

    expect(result.isError).toBeUndefined();
    const parsed = JSON.parse(result.content[0].type === "text" ? result.content[0].text : "");
    expect(parsed.operation.op).toBe("setExercisePhoto");
    // The image itself is never echoed back into the conversation.
    expect(result.content[0].type === "text" && result.content[0].text).not.toContain(JPEG_B64);
  });

  it("surfaces validation failures as tool errors", async () => {
    const result = await handleToolCall("attach_exercise_photo", {
      externalId: "../x",
      imageBase64: JPEG_B64,
    });
    expect(result.isError).toBe(true);
  });
});
