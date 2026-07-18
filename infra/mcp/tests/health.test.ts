/**
 * Tests for the health diagnostic tool — issue #79.
 *
 * Reports Functions API connectivity + auth status + base URL.
 * Must never expose the API key.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mockApiGet = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet };
});

const { ApiError } = await import("../src/shared/http.js");
const { health } = await import("../src/tools/health.js");

const BASE_URL = "https://func-workout-prod.azurewebsites.net";
const API_KEY = "super-secret-key";

const serverHealth = {
  status: "healthy",
  timestamp: "2026-07-18T10:00:00Z",
  version: "2.0.0",
};

beforeEach(() => {
  vi.stubEnv("FUNCTIONS_BASE_URL", BASE_URL);
  vi.stubEnv("FUNCTIONS_API_KEY", API_KEY);
  mockApiGet.mockReset();
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("health", () => {
  it("reports reachable + authValid when both checks pass", async () => {
    mockApiGet.mockImplementation(async (path: string) => {
      if (path === "health") return serverHealth;
      return { templates: [] };
    });

    const report = await health();

    expect(report.baseUrl).toBe(BASE_URL);
    expect(report.apiKeyConfigured).toBe(true);
    expect(report.reachable).toBe(true);
    expect(report.authValid).toBe(true);
    expect(report.server).toEqual(serverHealth);
  });

  it("reports authValid false on 401 without leaking the key", async () => {
    mockApiGet.mockImplementation(async (path: string) => {
      if (path === "health") return serverHealth;
      throw new ApiError(401, "Unauthorized: invalid or missing API key");
    });

    const report = await health();

    expect(report.reachable).toBe(true);
    expect(report.authValid).toBe(false);
    expect(JSON.stringify(report)).not.toContain(API_KEY);
    expect(report.error).toMatch(/api key/i);
  });

  it("reports unreachable when the health endpoint cannot be reached", async () => {
    mockApiGet.mockRejectedValue(
      new Error(`Cannot reach Functions API at ${BASE_URL}: fetch failed`)
    );

    const report = await health();

    expect(report.reachable).toBe(false);
    expect(report.authValid).toBeUndefined();
    expect(JSON.stringify(report)).not.toContain(API_KEY);
  });

  it("reports missing configuration without calling the API", async () => {
    vi.stubEnv("FUNCTIONS_BASE_URL", "");
    vi.stubEnv("FUNCTIONS_API_KEY", "");

    const report = await health();

    expect(report.apiKeyConfigured).toBe(false);
    expect(report.reachable).toBe(false);
    expect(report.error).toMatch(/FUNCTIONS_BASE_URL/);
    expect(mockApiGet).not.toHaveBeenCalled();
  });
});
