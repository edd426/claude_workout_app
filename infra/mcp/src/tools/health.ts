/**
 * Health diagnostic tool — issue #79.
 *
 * Reports Functions API connectivity, auth status, and the configured base
 * URL. The API key value is NEVER included in the report — only whether one
 * is configured.
 */

import { apiGet, ApiError } from "../shared/http.js";

export interface HealthReport {
  baseUrl: string;
  apiKeyConfigured: boolean;
  reachable: boolean;
  server?: { status: string; timestamp: string; version: string };
  authValid?: boolean;
  error?: string;
}

function messageOf(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

export async function health(): Promise<HealthReport> {
  const baseUrlRaw = process.env.FUNCTIONS_BASE_URL;
  const apiKeyConfigured = Boolean(process.env.FUNCTIONS_API_KEY);

  const report: HealthReport = {
    baseUrl: baseUrlRaw
      ? baseUrlRaw.replace(/\/+$/, "")
      : "(FUNCTIONS_BASE_URL not set)",
    apiKeyConfigured,
    reachable: false,
  };

  if (!baseUrlRaw || !apiKeyConfigured) {
    report.error =
      "Missing configuration: set the FUNCTIONS_BASE_URL and " +
      "FUNCTIONS_API_KEY environment variables in the MCP server config.";
    return report;
  }

  // 1. Connectivity: /api/health is anonymous, so this checks reachability
  //    and that the Function App is up, independent of the API key.
  try {
    report.server = await apiGet<{
      status: string;
      timestamp: string;
      version: string;
    }>("health");
    report.reachable = true;
  } catch (err) {
    report.error = `Functions API unreachable: ${messageOf(err)}`;
    return report;
  }

  // 2. Auth: hit a minimal authenticated endpoint to validate the API key.
  try {
    await apiGet("templates", { limit: 1 });
    report.authValid = true;
  } catch (err) {
    report.authValid = false;
    if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
      report.error =
        `API key rejected (${err.status}) — check that FUNCTIONS_API_KEY ` +
        "matches the API_KEY app setting on the Function App.";
    } else {
      report.error = `Auth check failed: ${messageOf(err)}`;
    }
  }

  return report;
}
