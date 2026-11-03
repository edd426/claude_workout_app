/**
 * Authenticated Streamable HTTP endpoint for the workout MCP server — issue #162.
 *
 * Stateless: each request gets a fresh transport and server, with JSON
 * responses instead of SSE streams. That fits Azure Functions (no sticky
 * sessions, no long-lived connections) and matches personal_memory, whose
 * connector already works from claude.ai this way.
 */

import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";

import { isAllowedUser } from "./auth.js";

/**
 * Largest /mcp request body read, in bytes. attach_exercise_photo (#170) takes
 * a JPEG of up to 3.75 MB as base64, a ~5 MB request, over the SDK's 4 MiB
 * default. The transport parses it only after the token and the oid
 * allowlist have passed (the Azure adapter has already buffered it by then).
 */
export const MAX_MCP_REQUEST_BYTES = 6 * 1024 * 1024;

export interface McpHandlerDeps {
  /** Verifies a bearer token and returns the caller's Entra object id; throws if invalid. */
  verify: (token: string) => Promise<{ oid: string }>;
  allowedOids: Set<string>;
  /** Absolute URL of the protected resource metadata, advertised in 401 challenges. */
  resourceMetadataUrl: string;
  createServer: () => Server;
  log?: (message: string) => void;
}

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

export async function handleMcpRequest(request: Request, deps: McpHandlerDeps): Promise<Response> {
  const challenge = {
    "www-authenticate":
      `Bearer error="invalid_token", error_description="A valid access token is required", ` +
      `resource_metadata="${deps.resourceMetadataUrl}"`,
  };

  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match) {
    return json(401, { error: "invalid_token" }, challenge);
  }

  let oid: string;
  try {
    ({ oid } = await deps.verify(match[1]));
  } catch (error) {
    // The reason goes to the log only; callers learn nothing about why.
    deps.log?.(`token rejected: ${error instanceof Error ? error.message : String(error)}`);
    return json(401, { error: "invalid_token" }, challenge);
  }

  if (!isAllowedUser(oid, deps.allowedOids)) {
    deps.log?.(`valid token for an oid not in ALLOWED_OIDS: ${oid}`);
    return json(403, { error: "forbidden" });
  }

  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
    maxRequestBodySize: MAX_MCP_REQUEST_BYTES,
  });
  const server = deps.createServer();
  try {
    await server.connect(transport);
    return await transport.handleRequest(request);
  } finally {
    await transport.close().catch(() => undefined);
    await server.close().catch(() => undefined);
  }
}
