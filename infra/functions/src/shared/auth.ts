import { HttpRequest, HttpResponseInit } from "@azure/functions";

/**
 * Validates the x-api-key header against the API_KEY environment variable.
 * Returns null if authentication passes, or an error response if it fails.
 */
export function authenticate(request: HttpRequest): HttpResponseInit | null {
  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    return {
      status: 500,
      jsonBody: { error: "Server misconfigured: API_KEY not set" },
    };
  }

  const providedKey = request.headers.get("x-api-key");
  if (!providedKey || providedKey !== apiKey) {
    return {
      status: 401,
      jsonBody: { error: "Unauthorized: invalid or missing API key" },
    };
  }

  return null;
}
