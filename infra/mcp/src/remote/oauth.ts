/**
 * OAuth proxy in front of Entra ID for the claude.ai connector — issue #162.
 *
 * claude.ai speaks MCP authorization: it discovers this server's metadata,
 * registers itself dynamically (RFC 7591), and runs an authorization-code
 * flow with PKCE. Entra ID supports none of the discovery or registration
 * parts, so this module answers them and forwards the real work to Entra:
 * every client maps to our single Entra app, and the token exchange adds the
 * app's client secret server-side.
 *
 * Pure functions only (no I/O) so every rule here is unit-tested; the HTTP
 * wiring lives in azure/functions.ts. Pattern from personal_memory, tightened:
 * exact redirect-URI matching, PKCE S256 required, and the token proxy only
 * spends the client secret on the two grants claude.ai uses.
 */

import { REQUIRED_SCOPE, type EntraConfig } from "./auth.js";

/**
 * Claude's OAuth callbacks. The Entra app registers exactly these, which is the
 * real control (anyone can call Entra's authorize endpoint directly); the proxy
 * checks them too so it never forwards anything else.
 */
export const CLAUDE_REDIRECT_URIS: readonly string[] = [
  "https://claude.ai/api/mcp/auth_callback",
  "https://claude.com/api/mcp/auth_callback",
];

export function isAllowedRedirectUri(uri: unknown): boolean {
  return typeof uri === "string" && CLAUDE_REDIRECT_URIS.includes(uri);
}

export function apiScope(clientId: string): string {
  return `api://${clientId}/${REQUIRED_SCOPE}`;
}

/** What we always ask Entra for, whatever scope the client sent. */
export function requestedScopes(clientId: string): string {
  return `${apiScope(clientId)} openid profile offline_access`;
}

/** RFC 9728 protected resource metadata for `${baseUrl}/mcp`. */
export function protectedResourceMetadata(baseUrl: string, clientId: string) {
  return {
    resource: `${baseUrl}/mcp`,
    authorization_servers: [baseUrl],
    scopes_supported: [apiScope(clientId)],
    bearer_methods_supported: ["header"],
    resource_name: "ClaudeLifter Workout MCP",
  };
}

/** RFC 8414 authorization server metadata; this server is the issuer. */
export function authorizationServerMetadata(baseUrl: string, clientId: string) {
  return {
    issuer: baseUrl,
    authorization_endpoint: `${baseUrl}/authorize`,
    token_endpoint: `${baseUrl}/token`,
    registration_endpoint: `${baseUrl}/register`,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
    scopes_supported: [apiScope(clientId)],
  };
}

export interface JsonResult {
  status: number;
  body: Record<string, unknown>;
}

function oauthError(error: string, description: string): JsonResult {
  return { status: 400, body: { error, error_description: description } };
}

/**
 * RFC 7591 dynamic client registration. Every registration maps to the one
 * Entra app; no secret is ever issued (the proxy holds it), so clients are
 * public clients protected by PKCE.
 */
export function registerClient(body: unknown, clientId: string): JsonResult {
  if (body === null || typeof body !== "object") {
    return oauthError("invalid_client_metadata", "Request body must be a JSON object");
  }
  const meta = body as Record<string, unknown>;
  const uris = meta.redirect_uris;
  if (!Array.isArray(uris) || uris.length === 0) {
    return oauthError("invalid_client_metadata", "redirect_uris must be a non-empty array");
  }
  if (!uris.every(isAllowedRedirectUri)) {
    return oauthError("invalid_redirect_uri", "Only Claude's OAuth callbacks are allowed");
  }
  return {
    status: 201,
    body: {
      client_id: clientId,
      client_name: typeof meta.client_name === "string" ? meta.client_name : "MCP Client",
      redirect_uris: uris,
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
      client_id_issued_at: Math.floor(Date.now() / 1000),
    },
  };
}

export type AuthorizeResult =
  | { status: 302; location: string }
  | { status: 400; body: Record<string, unknown> };

/** Validate claude.ai's authorize request and redirect it to Entra. */
export function authorizeRedirect(query: URLSearchParams, config: EntraConfig): AuthorizeResult {
  const reject = (description: string): AuthorizeResult => ({
    status: 400,
    body: { error: "invalid_request", error_description: description },
  });

  if (!isAllowedRedirectUri(query.get("redirect_uri"))) return reject("redirect_uri not allowed");
  if (query.get("response_type") !== "code") return reject("response_type must be code");
  if (!query.get("code_challenge")) return reject("code_challenge is required");
  if (query.get("code_challenge_method") !== "S256") return reject("code_challenge_method must be S256");

  const target = new URL(
    `https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/authorize`
  );
  for (const name of ["response_type", "redirect_uri", "state", "code_challenge", "code_challenge_method"]) {
    const value = query.get(name);
    if (value) target.searchParams.set(name, value);
  }
  target.searchParams.set("client_id", config.clientId);
  target.searchParams.set("scope", requestedScopes(config.clientId));
  return { status: 302, location: target.toString() };
}

export type TokenRequest =
  | { ok: true; url: string; body: URLSearchParams }
  | { ok: false; error: string; description: string };

/**
 * Turn claude.ai's token request into Entra's, adding our credentials.
 * Only the authorization-code (with PKCE and an allowed redirect) and
 * refresh-token grants are forwarded.
 */
export function buildTokenRequest(
  form: URLSearchParams,
  config: EntraConfig & { clientSecret: string }
): TokenRequest {
  const fail = (error: string, description: string): TokenRequest => ({ ok: false, error, description });
  const grant = form.get("grant_type");
  const body = new URLSearchParams();
  body.set("client_id", config.clientId);
  body.set("client_secret", config.clientSecret);
  body.set("scope", requestedScopes(config.clientId));

  if (grant === "authorization_code") {
    const code = form.get("code");
    const verifier = form.get("code_verifier");
    const redirect = form.get("redirect_uri");
    if (!code) return fail("invalid_request", "code is required");
    if (!verifier) return fail("invalid_request", "code_verifier is required");
    if (!isAllowedRedirectUri(redirect)) return fail("invalid_grant", "redirect_uri not allowed");
    body.set("grant_type", grant);
    body.set("code", code);
    body.set("code_verifier", verifier);
    body.set("redirect_uri", redirect as string);
  } else if (grant === "refresh_token") {
    const refresh = form.get("refresh_token");
    if (!refresh) return fail("invalid_request", "refresh_token is required");
    body.set("grant_type", grant);
    body.set("refresh_token", refresh);
  } else {
    return fail("unsupported_grant_type", "Only authorization_code and refresh_token are supported");
  }

  return {
    ok: true,
    url: `https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/token`,
    body,
  };
}
