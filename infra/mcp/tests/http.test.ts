/**
 * Tests for the Functions API HTTP client — issue #79.
 *
 * The MCP server no longer talks to Cosmos DB via DefaultAzureCredential; it
 * is a thin HTTP client of the Azure Functions API, authenticated with the
 * same x-api-key shared secret the iOS app uses.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const http = await import("../src/shared/http.js");
const { apiGet, ApiError } = http;

const BASE_URL = "https://func-workout-prod.azurewebsites.net";
const API_KEY = "super-secret-key";

function jsonResponse(body: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

const mockFetch = vi.fn();

beforeEach(() => {
  vi.stubGlobal("fetch", mockFetch);
  vi.stubEnv("FUNCTIONS_BASE_URL", BASE_URL);
  vi.stubEnv("FUNCTIONS_API_KEY", API_KEY);
  mockFetch.mockReset();
  mockFetch.mockResolvedValue(jsonResponse({}));
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe("apiGet", () => {
  it("throws when FUNCTIONS_BASE_URL is not set", async () => {
    vi.stubEnv("FUNCTIONS_BASE_URL", "");
    await expect(apiGet("health")).rejects.toThrow(/FUNCTIONS_BASE_URL/);
  });

  it("throws when FUNCTIONS_API_KEY is not set", async () => {
    vi.stubEnv("FUNCTIONS_API_KEY", "");
    await expect(apiGet("health")).rejects.toThrow(/FUNCTIONS_API_KEY/);
  });

  it("requests {base}/api/{path} with the x-api-key header", async () => {
    await apiGet("templates");

    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, init] = mockFetch.mock.calls[0];
    expect(String(url)).toBe(`${BASE_URL}/api/templates`);
    expect(init.headers["x-api-key"]).toBe(API_KEY);
  });

  it("strips a trailing slash from the base URL", async () => {
    vi.stubEnv("FUNCTIONS_BASE_URL", `${BASE_URL}/`);
    await apiGet("health");
    const [url] = mockFetch.mock.calls[0];
    expect(String(url)).toBe(`${BASE_URL}/api/health`);
  });

  it("serializes defined query params and omits undefined ones", async () => {
    await apiGet("workouts", {
      startDate: "2026-03-01",
      endDate: undefined,
      limit: 25,
    });

    const [url] = mockFetch.mock.calls[0];
    const parsed = new URL(String(url));
    expect(parsed.searchParams.get("startDate")).toBe("2026-03-01");
    expect(parsed.searchParams.get("limit")).toBe("25");
    expect(parsed.searchParams.has("endDate")).toBe(false);
  });

  it("returns the parsed JSON body", async () => {
    mockFetch.mockResolvedValue(jsonResponse({ templates: [{ id: "t1" }] }));
    const result = await apiGet<{ templates: { id: string }[] }>("templates");
    expect(result.templates).toEqual([{ id: "t1" }]);
  });

  it("throws ApiError with the status and server detail on non-2xx", async () => {
    mockFetch.mockResolvedValue(
      jsonResponse({ error: "Template not found: t9" }, 404)
    );

    try {
      await apiGet("templates/t9");
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ApiError);
      expect((err as InstanceType<typeof ApiError>).status).toBe(404);
      expect((err as Error).message).toContain("404");
      expect((err as Error).message).toContain("Template not found: t9");
    }
  });

  it("never includes the API key in error messages", async () => {
    mockFetch.mockResolvedValue(jsonResponse({ error: "Unauthorized" }, 401));
    await expect(apiGet("templates")).rejects.toThrow();
    try {
      await apiGet("templates");
    } catch (err) {
      expect((err as Error).message).not.toContain(API_KEY);
    }
  });

  it("wraps network failures with a message naming the base URL", async () => {
    mockFetch.mockRejectedValue(new TypeError("fetch failed"));
    try {
      await apiGet("health");
      expect.unreachable("should have thrown");
    } catch (err) {
      expect((err as Error).message).toContain(BASE_URL);
      expect((err as Error).message).not.toContain(API_KEY);
    }
  });
});

describe("apiPost", () => {
  it("is exposed by the shared HTTP layer", () => {
    expect("apiPost" in http).toBe(true);
  });

  it("posts JSON to {base}/api/{path} with the API key", async () => {
    mockFetch.mockResolvedValue(jsonResponse({ id: "op-1" }));

    const apiPost = (
      http as typeof http & {
        apiPost<T>(path: string, body: unknown): Promise<T>;
      }
    ).apiPost;
    const result = await apiPost<{ id: string }>("inbox", {
      op: "deleteTemplate",
      payload: { id: "template-1", name: "Push Day" },
    });

    expect(result).toEqual({ id: "op-1" });
    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, init] = mockFetch.mock.calls[0];
    expect(String(url)).toBe(`${BASE_URL}/api/inbox`);
    expect(init).toMatchObject({
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": API_KEY,
      },
    });
    expect(JSON.parse(init.body)).toEqual({
      op: "deleteTemplate",
      payload: { id: "template-1", name: "Push Day" },
    });
  });

  it("reports POST and the server detail for non-2xx responses", async () => {
    mockFetch.mockResolvedValue(
      jsonResponse({ error: "Malformed payload: name is required" }, 400)
    );

    const apiPost = (
      http as typeof http & {
        apiPost<T>(path: string, body: unknown): Promise<T>;
      }
    ).apiPost;

    await expect(apiPost("inbox", {})).rejects.toThrow(
      /Malformed payload: name is required.*POST \/api\/inbox/
    );
  });
});
