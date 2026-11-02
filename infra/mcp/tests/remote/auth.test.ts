/** Tests for Entra ID access-token verification on the remote MCP endpoint — issue #162. */

import { describe, it, expect, beforeAll } from "vitest";
import * as jose from "jose";

import {
  REQUIRED_SCOPE,
  verifyAccessToken,
  parseAllowedOids,
  isAllowedUser,
  entraConfigFromEnv,
} from "../../src/remote/auth.js";

const TENANT = "11111111-2222-3333-4444-555555555555";
const CLIENT = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const OID = "99999999-8888-7777-6666-555555555555";
const config = { tenantId: TENANT, clientId: CLIENT };

let privateKey: CryptoKey;
let getKey: jose.JWTVerifyGetKey;
let otherPrivateKey: CryptoKey;

beforeAll(async () => {
  const pair = await jose.generateKeyPair("RS256");
  privateKey = pair.privateKey;
  const jwk = await jose.exportJWK(pair.publicKey);
  jwk.kid = "test-key";
  jwk.alg = "RS256";
  getKey = jose.createLocalJWKSet({ keys: [jwk] });
  otherPrivateKey = (await jose.generateKeyPair("RS256")).privateKey;
});

interface TokenOptions {
  iss?: string;
  aud?: string;
  scp?: string | undefined;
  tid?: string | undefined;
  oid?: string | undefined;
  expiresIn?: string;
  key?: CryptoKey;
}

async function token(opts: TokenOptions = {}): Promise<string> {
  const claims: Record<string, unknown> = {};
  if (!("scp" in opts) || opts.scp !== undefined) claims.scp = opts.scp ?? REQUIRED_SCOPE;
  if (!("tid" in opts) || opts.tid !== undefined) claims.tid = opts.tid ?? TENANT;
  if (!("oid" in opts) || opts.oid !== undefined) claims.oid = opts.oid ?? OID;
  return new jose.SignJWT(claims)
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setIssuer(opts.iss ?? `https://login.microsoftonline.com/${TENANT}/v2.0`)
    .setAudience(opts.aud ?? CLIENT)
    .setIssuedAt()
    .setExpirationTime(opts.expiresIn ?? "1h")
    .sign(opts.key ?? privateKey);
}

describe("verifyAccessToken", () => {
  it("accepts a v2 access token for this API and returns the caller's oid", async () => {
    const result = await verifyAccessToken(await token(), config, getKey);
    expect(result.oid).toBe(OID);
  });

  it("accepts a v1 access token (sts.windows.net issuer, api:// audience)", async () => {
    const t = await token({ iss: `https://sts.windows.net/${TENANT}/`, aud: `api://${CLIENT}` });
    const result = await verifyAccessToken(t, config, getKey);
    expect(result.oid).toBe(OID);
  });

  it("accepts the scope among several granted scopes", async () => {
    const t = await token({ scp: `openid ${REQUIRED_SCOPE} profile` });
    await expect(verifyAccessToken(t, config, getKey)).resolves.toEqual({ oid: OID });
  });

  it("rejects an ID token, which has the same issuer and audience but no scp", async () => {
    const t = await token({ scp: undefined });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow(/scope/);
  });

  it("rejects a token carrying a different scope", async () => {
    const t = await token({ scp: "User.Read" });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow(/scope/);
  });

  it("rejects a token issued for another application", async () => {
    const t = await token({ aud: "someone-elses-client-id" });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow();
  });

  it("rejects a token from another tenant's issuer", async () => {
    const t = await token({ iss: "https://login.microsoftonline.com/other-tenant/v2.0" });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow();
  });

  it("rejects a token whose tid claim names another tenant", async () => {
    const t = await token({ tid: "other-tenant" });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow(/tenant/);
  });

  it("rejects a token without an oid", async () => {
    const t = await token({ oid: undefined });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow(/oid/);
  });

  it("rejects an expired token", async () => {
    const t = await token({ expiresIn: "-5m" });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow();
  });

  it("rejects a token signed by a key that is not in the JWKS", async () => {
    const t = await token({ key: otherPrivateKey });
    await expect(verifyAccessToken(t, config, getKey)).rejects.toThrow();
  });

  it("rejects an unsigned (alg none) token", async () => {
    const unsigned = new jose.UnsecuredJWT({ scp: REQUIRED_SCOPE, tid: TENANT, oid: OID })
      .setIssuer(`https://login.microsoftonline.com/${TENANT}/v2.0`)
      .setAudience(CLIENT)
      .setExpirationTime("1h")
      .encode();
    await expect(verifyAccessToken(unsigned, config, getKey)).rejects.toThrow();
  });

  it("rejects garbage", async () => {
    await expect(verifyAccessToken("not-a-jwt", config, getKey)).rejects.toThrow();
  });
});

describe("allowlist", () => {
  it("parses comma-separated oids, trimming and lower-casing", () => {
    expect(parseAllowedOids(" ABC , def,, ")).toEqual(new Set(["abc", "def"]));
  });

  it("fails closed: an unset or empty allowlist admits nobody", () => {
    expect(isAllowedUser(OID, parseAllowedOids(undefined))).toBe(false);
    expect(isAllowedUser(OID, parseAllowedOids("  "))).toBe(false);
  });

  it("admits only listed oids, case-insensitively", () => {
    const allowed = parseAllowedOids(OID.toUpperCase());
    expect(isAllowedUser(OID, allowed)).toBe(true);
    expect(isAllowedUser("someone-else", allowed)).toBe(false);
  });
});

describe("entraConfigFromEnv", () => {
  it("reads tenant and client ids", () => {
    expect(entraConfigFromEnv({ ENTRA_TENANT_ID: TENANT, ENTRA_CLIENT_ID: CLIENT })).toEqual(config);
  });

  it("throws when either id is missing", () => {
    expect(() => entraConfigFromEnv({ ENTRA_TENANT_ID: TENANT })).toThrow(/ENTRA_CLIENT_ID/);
    expect(() => entraConfigFromEnv({ ENTRA_CLIENT_ID: CLIENT })).toThrow(/ENTRA_TENANT_ID/);
  });
});
