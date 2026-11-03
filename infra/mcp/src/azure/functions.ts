/**
 * Azure Functions entry point for the claude.ai connector — issue #162.
 *
 * Deployed to its own Function App (func-workout-mcp-prod), separate from the
 * phone's API (func-workout-prod). The tools are the same ones the stdio
 * server exposes and still reach data only through the Functions API with
 * FUNCTIONS_API_KEY, which stays server-side.
 *
 * Routes (host.json sets routePrefix to ""):
 *   POST|GET|DELETE /mcp                              MCP Streamable HTTP, bearer-protected
 *   GET  /.well-known/oauth-protected-resource/mcp    RFC 9728
 *   GET  /.well-known/oauth-authorization-server      RFC 8414
 *   POST /register                                    RFC 7591 (maps to the one Entra app)
 *   GET  /authorize                                   redirect to Entra
 *   POST /token                                       proxy to Entra, adds the client secret
 *   GET  /health                                      liveness only, no secrets
 *
 * Settings: PUBLIC_BASE_URL, ENTRA_TENANT_ID, ENTRA_CLIENT_ID,
 * ENTRA_CLIENT_SECRET, ALLOWED_OIDS, FUNCTIONS_BASE_URL, FUNCTIONS_API_KEY.
 */

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";

import { createWorkoutServer } from "../serverFactory.js";
import { entraConfigFromEnv, parseAllowedOids, verifyAccessToken } from "../remote/auth.js";
import { handleMcpRequest } from "../remote/mcpHandler.js";
import {
  authorizationServerMetadata,
  authorizeRedirect,
  buildTokenRequest,
  protectedResourceMetadata,
  registerClient,
} from "../remote/oauth.js";
import { toHttpResponse, toWebRequest } from "../remote/adapters.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const NOT_CONFIGURED: HttpResponseInit = { status: 500, jsonBody: { error: "server_not_configured" } };

function baseUrl(): string {
  const raw = process.env.PUBLIC_BASE_URL;
  if (!raw) throw new Error("PUBLIC_BASE_URL environment variable not configured");
  return raw.replace(/\/+$/, "");
}

/** Run a handler, turning configuration errors into a bare 500 with the detail logged. */
async function guarded(
  context: InvocationContext,
  fn: () => Promise<HttpResponseInit>
): Promise<HttpResponseInit> {
  try {
    return await fn();
  } catch (error) {
    context.error(`request failed: ${error instanceof Error ? error.message : String(error)}`);
    return NOT_CONFIGURED;
  }
}

async function mcp(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return guarded(context, async () => {
    const config = entraConfigFromEnv();
    const allowedOids = parseAllowedOids(process.env.ALLOWED_OIDS);
    const res = await handleMcpRequest(await toWebRequest(request), {
      verify: (token) => verifyAccessToken(token, config),
      allowedOids,
      resourceMetadataUrl: `${baseUrl()}/.well-known/oauth-protected-resource/mcp`,
      // Remote: never read files on the Function host (attach_exercise_photo's imagePath).
      createServer: () => createWorkoutServer({ allowLocalFiles: false }),
      log: (message) => context.warn(message),
    });
    return toHttpResponse(res);
  });
}

async function resourceMetadata(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  if (request.method === "OPTIONS") return { status: 204, headers: CORS };
  return guarded(context, async () => ({
    status: 200,
    headers: { "Cache-Control": "public, max-age=3600", ...CORS },
    jsonBody: protectedResourceMetadata(baseUrl(), entraConfigFromEnv().clientId),
  }));
}

async function serverMetadata(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  if (request.method === "OPTIONS") return { status: 204, headers: CORS };
  return guarded(context, async () => ({
    status: 200,
    headers: { "Cache-Control": "public, max-age=3600", ...CORS },
    jsonBody: authorizationServerMetadata(baseUrl(), entraConfigFromEnv().clientId),
  }));
}

async function register(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return guarded(context, async () => {
    let body: unknown = null;
    try {
      body = await request.json();
    } catch {
      body = null;
    }
    const result = registerClient(body, entraConfigFromEnv().clientId);
    return { status: result.status, headers: { "Cache-Control": "no-store" }, jsonBody: result.body };
  });
}

async function authorize(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return guarded(context, async () => {
    const result = authorizeRedirect(new URL(request.url).searchParams, entraConfigFromEnv());
    if (result.status === 302) {
      return { status: 302, headers: { Location: result.location, "Cache-Control": "no-store" } };
    }
    return { status: 400, jsonBody: result.body };
  });
}

async function token(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  return guarded(context, async (): Promise<HttpResponseInit> => {
    const clientSecret = process.env.ENTRA_CLIENT_SECRET;
    if (!clientSecret) throw new Error("ENTRA_CLIENT_SECRET environment variable not configured");
    const built = buildTokenRequest(new URLSearchParams(await request.text()), {
      ...entraConfigFromEnv(),
      clientSecret,
    });
    if (!built.ok) {
      return {
        status: 400,
        headers: { "Cache-Control": "no-store" },
        jsonBody: { error: built.error, error_description: built.description },
      };
    }
    const upstream = await fetch(built.url, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: built.body.toString(),
    });
    // Log the outcome only: the body carries tokens.
    context.log(`token exchange (${built.body.get("grant_type")}): Entra answered ${upstream.status}`);
    return {
      status: upstream.status,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store", Pragma: "no-cache" },
      body: await upstream.text(),
    };
  });
}

async function health(): Promise<HttpResponseInit> {
  return { status: 200, jsonBody: { status: "ok", service: "claudelifter-workout-mcp" } };
}

app.http("mcp", { methods: ["GET", "POST", "DELETE"], authLevel: "anonymous", route: "mcp", handler: mcp });
app.http("protectedResourceMetadata", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: ".well-known/oauth-protected-resource/mcp",
  handler: resourceMetadata,
});
app.http("authorizationServerMetadata", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: ".well-known/oauth-authorization-server",
  handler: serverMetadata,
});
app.http("register", { methods: ["POST"], authLevel: "anonymous", route: "register", handler: register });
app.http("authorize", { methods: ["GET"], authLevel: "anonymous", route: "authorize", handler: authorize });
app.http("token", { methods: ["POST"], authLevel: "anonymous", route: "token", handler: token });
app.http("health", { methods: ["GET"], authLevel: "anonymous", route: "health", handler: health });
