/**
 * Entra ID access-token verification for the remote MCP endpoint — issue #162.
 *
 * Adapted from personal_memory's src/azure/auth.ts, tightened in two places:
 * the token's `tid` must match our tenant, and an unset ALLOWED_OIDS admits
 * nobody (personal_memory admits the whole tenant and logs a warning).
 */

import * as jose from "jose";

/** The delegated scope exposed by the Entra app and requested by the OAuth proxy. */
export const REQUIRED_SCOPE = "workout.access";

export interface EntraConfig {
  tenantId: string;
  clientId: string;
}

type Env = Record<string, string | undefined>;

export function entraConfigFromEnv(env: Env = process.env): EntraConfig {
  const tenantId = env.ENTRA_TENANT_ID;
  const clientId = env.ENTRA_CLIENT_ID;
  if (!tenantId) throw new Error("ENTRA_TENANT_ID environment variable not configured");
  if (!clientId) throw new Error("ENTRA_CLIENT_ID environment variable not configured");
  return { tenantId, clientId };
}

const jwksByTenant = new Map<string, jose.JWTVerifyGetKey>();

/** Entra's signing keys for the tenant; jose caches and refreshes them itself. */
export function entraJwks(tenantId: string): jose.JWTVerifyGetKey {
  let jwks = jwksByTenant.get(tenantId);
  if (!jwks) {
    jwks = jose.createRemoteJWKSet(
      new URL(`https://login.microsoftonline.com/${tenantId}/discovery/v2.0/keys`)
    );
    jwksByTenant.set(tenantId, jwks);
  }
  return jwks;
}

/**
 * Verify an Entra access token for this API and return the caller's object id.
 *
 * Signature, expiry, issuer and audience are checked by jose. An ID token for
 * the same app passes all four, so the `scp` check is what rejects it: only
 * access tokens carry scopes.
 */
export async function verifyAccessToken(
  token: string,
  config: EntraConfig,
  getKey: jose.JWTVerifyGetKey = entraJwks(config.tenantId)
): Promise<{ oid: string }> {
  const { payload } = await jose.jwtVerify(token, getKey, {
    algorithms: ["RS256"],
    audience: [config.clientId, `api://${config.clientId}`],
    issuer: [
      `https://login.microsoftonline.com/${config.tenantId}/v2.0`,
      `https://sts.windows.net/${config.tenantId}/`,
    ],
  });

  if (payload.tid !== config.tenantId) {
    throw new Error("Token issued for another tenant");
  }
  if (typeof payload.oid !== "string" || payload.oid.length === 0) {
    throw new Error("Token missing required claim: oid");
  }
  const scopes = typeof payload.scp === "string" ? payload.scp.split(" ") : [];
  if (!scopes.includes(REQUIRED_SCOPE)) {
    throw new Error(`Token missing required scope: ${REQUIRED_SCOPE}`);
  }
  return { oid: payload.oid };
}

/** Parse ALLOWED_OIDS (comma-separated Entra object ids). Unset or blank → empty set. */
export function parseAllowedOids(raw: string | undefined): Set<string> {
  return new Set(
    (raw ?? "")
      .split(",")
      .map((oid) => oid.trim().toLowerCase())
      .filter((oid) => oid.length > 0)
  );
}

/** Fails closed: an empty allowlist admits nobody. */
export function isAllowedUser(oid: string, allowed: Set<string>): boolean {
  return allowed.has(oid.toLowerCase());
}
