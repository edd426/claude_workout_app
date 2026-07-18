/**
 * HTTP client for the ClaudeLifter Azure Functions API — issue #79.
 *
 * The MCP server no longer talks to Cosmos DB directly (DefaultAzureCredential
 * had no data-plane rights, so every query 403'd). All data access goes
 * through the Functions API using the same x-api-key shared secret the iOS
 * app uses: one auth path, one data-access layer.
 *
 * Configuration (environment variables):
 *   FUNCTIONS_BASE_URL — e.g. https://func-workout-prod.azurewebsites.net
 *   FUNCTIONS_API_KEY  — the shared secret validated by the Functions API
 *
 * The API key is never logged and never included in error messages.
 */

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

export interface ApiConfig {
  baseUrl: string;
  apiKey: string;
}

export function getConfig(): ApiConfig {
  const baseUrl = process.env.FUNCTIONS_BASE_URL;
  if (!baseUrl) {
    throw new Error(
      "FUNCTIONS_BASE_URL environment variable not configured " +
        "(e.g. https://func-workout-prod.azurewebsites.net)"
    );
  }
  const apiKey = process.env.FUNCTIONS_API_KEY;
  if (!apiKey) {
    throw new Error("FUNCTIONS_API_KEY environment variable not configured");
  }
  return { baseUrl: baseUrl.replace(/\/+$/, ""), apiKey };
}

export type QueryParams = Record<string, string | number | undefined>;

export async function apiGet<T = unknown>(
  path: string,
  params?: QueryParams
): Promise<T> {
  const { baseUrl, apiKey } = getConfig();

  const url = new URL(`${baseUrl}/api/${path}`);
  for (const [name, value] of Object.entries(params ?? {})) {
    if (value !== undefined) {
      url.searchParams.set(name, String(value));
    }
  }

  let response: Response;
  try {
    response = await fetch(url, { headers: { "x-api-key": apiKey } });
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Cannot reach Functions API at ${baseUrl}: ${detail}`);
  }

  if (!response.ok) {
    let detail = "";
    try {
      const body = (await response.json()) as { error?: string };
      detail = body?.error ?? "";
    } catch {
      // Non-JSON error body — status alone will have to do.
    }
    throw new ApiError(
      response.status,
      `Functions API returned ${response.status}` +
        (detail ? `: ${detail}` : "") +
        ` (GET /api/${path})`
    );
  }

  return (await response.json()) as T;
}
