/** Tests for the OAuth proxy that fronts Entra ID for claude.ai — issue #162. */

import { describe, it, expect } from "vitest";

import { REQUIRED_SCOPE } from "../../src/remote/auth.js";
import {
  CLAUDE_REDIRECT_URIS,
  isAllowedRedirectUri,
  protectedResourceMetadata,
  authorizationServerMetadata,
  registerClient,
  authorizeRedirect,
  buildTokenRequest,
} from "../../src/remote/oauth.js";

const BASE = "https://func-workout-mcp-prod.azurewebsites.net";
const TENANT = "11111111-2222-3333-4444-555555555555";
const CLIENT = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const cfg = { tenantId: TENANT, clientId: CLIENT };
const CALLBACK = "https://claude.ai/api/mcp/auth_callback";
const SCOPE = `api://${CLIENT}/${REQUIRED_SCOPE} openid profile offline_access`;

describe("redirect URI allowlist", () => {
  it("allows exactly Claude's two callbacks", () => {
    expect(CLAUDE_REDIRECT_URIS).toEqual([
      "https://claude.ai/api/mcp/auth_callback",
      "https://claude.com/api/mcp/auth_callback",
    ]);
    for (const uri of CLAUDE_REDIRECT_URIS) expect(isAllowedRedirectUri(uri)).toBe(true);
  });

  it.each([
    "https://claude.ai/",
    "https://claude.ai/api/mcp/auth_callback/extra",
    "https://claude.ai/api/mcp/auth_callback?x=1",
    "https://claude.ai.evil.example/api/mcp/auth_callback",
    "http://claude.ai/api/mcp/auth_callback",
    "https://evil.example/?https://claude.ai/api/mcp/auth_callback",
    "",
  ])("rejects %j", (uri) => {
    expect(isAllowedRedirectUri(uri)).toBe(false);
  });

  it("rejects non-strings", () => {
    expect(isAllowedRedirectUri(undefined)).toBe(false);
    expect(isAllowedRedirectUri(null)).toBe(false);
    expect(isAllowedRedirectUri(42)).toBe(false);
  });
});

describe("discovery metadata", () => {
  it("describes the protected resource (RFC 9728)", () => {
    expect(protectedResourceMetadata(BASE, CLIENT)).toEqual({
      resource: `${BASE}/mcp`,
      authorization_servers: [BASE],
      scopes_supported: [`api://${CLIENT}/${REQUIRED_SCOPE}`],
      bearer_methods_supported: ["header"],
      resource_name: "ClaudeLifter Workout MCP",
    });
  });

  it("describes the authorization server (RFC 8414) with PKCE S256 only", () => {
    const meta = authorizationServerMetadata(BASE, CLIENT);
    expect(meta.issuer).toBe(BASE);
    expect(meta.authorization_endpoint).toBe(`${BASE}/authorize`);
    expect(meta.token_endpoint).toBe(`${BASE}/token`);
    expect(meta.registration_endpoint).toBe(`${BASE}/register`);
    expect(meta.code_challenge_methods_supported).toEqual(["S256"]);
    expect(meta.grant_types_supported).toEqual(["authorization_code", "refresh_token"]);
    expect(meta.response_types_supported).toEqual(["code"]);
  });
});

describe("dynamic client registration (RFC 7591)", () => {
  it("maps every registration to the one Entra app", () => {
    const res = registerClient({ client_name: "Claude", redirect_uris: [CALLBACK] }, CLIENT);
    expect(res.status).toBe(201);
    expect(res.body.client_id).toBe(CLIENT);
    expect(res.body.redirect_uris).toEqual([CALLBACK]);
    expect(res.body.token_endpoint_auth_method).toBe("none");
  });

  it("never returns a client secret", () => {
    const res = registerClient({ redirect_uris: [CALLBACK], token_endpoint_auth_method: "client_secret_post" }, CLIENT);
    expect(JSON.stringify(res.body)).not.toMatch(/secret"\s*:\s*"/);
    expect(res.body.token_endpoint_auth_method).toBe("none");
  });

  it.each([
    [{}, "missing redirect_uris"],
    [{ redirect_uris: [] }, "empty redirect_uris"],
    [{ redirect_uris: "https://claude.ai/api/mcp/auth_callback" }, "string redirect_uris"],
    [{ redirect_uris: [CALLBACK, "https://evil.example/cb"] }, "one disallowed redirect"],
    [null, "null body"],
  ])("rejects %j (%s)", (body) => {
    const res = registerClient(body, CLIENT);
    expect(res.status).toBe(400);
    expect(String(res.body.error)).toMatch(/invalid_(redirect_uri|client_metadata)/);
  });
});

describe("authorize redirect", () => {
  const valid = () =>
    new URLSearchParams({
      response_type: "code",
      client_id: "whatever-claude-sent",
      redirect_uri: CALLBACK,
      state: "st4te",
      code_challenge: "chal",
      code_challenge_method: "S256",
      scope: "claudeai",
      prompt: "none",
    });

  it("redirects to Entra with our client id and scope, forwarding PKCE and state", () => {
    const res = authorizeRedirect(valid(), cfg);
    expect(res.status).toBe(302);
    if (res.status !== 302) return;
    const url = new URL(res.location);
    expect(url.origin + url.pathname).toBe(
      `https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/authorize`
    );
    expect(url.searchParams.get("client_id")).toBe(CLIENT);
    expect(url.searchParams.get("scope")).toBe(SCOPE);
    expect(url.searchParams.get("redirect_uri")).toBe(CALLBACK);
    expect(url.searchParams.get("state")).toBe("st4te");
    expect(url.searchParams.get("code_challenge")).toBe("chal");
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.searchParams.get("response_type")).toBe("code");
    expect(url.searchParams.has("prompt")).toBe(false);
  });

  it.each([
    ["redirect_uri", undefined],
    ["redirect_uri", "https://evil.example/cb"],
    ["response_type", "token"],
    ["code_challenge", undefined],
    ["code_challenge_method", "plain"],
    ["code_challenge_method", undefined],
  ])("rejects when %s is %j", (name, value) => {
    const q = valid();
    if (value === undefined) q.delete(name);
    else q.set(name, value);
    const res = authorizeRedirect(q, cfg);
    expect(res.status).toBe(400);
  });
});

describe("token request", () => {
  const secret = "s3cr3t";

  it("exchanges an authorization code with our credentials and scope", () => {
    const form = new URLSearchParams({
      grant_type: "authorization_code",
      code: "the-code",
      redirect_uri: CALLBACK,
      code_verifier: "verifier",
      client_id: "whatever",
      scope: "claudeai",
    });
    const res = buildTokenRequest(form, { ...cfg, clientSecret: secret });
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.url).toBe(`https://login.microsoftonline.com/${TENANT}/oauth2/v2.0/token`);
    const b = res.body;
    expect(b.get("client_id")).toBe(CLIENT);
    expect(b.get("client_secret")).toBe(secret);
    expect(b.get("scope")).toBe(SCOPE);
    expect(b.get("grant_type")).toBe("authorization_code");
    expect(b.get("code")).toBe("the-code");
    expect(b.get("code_verifier")).toBe("verifier");
    expect(b.get("redirect_uri")).toBe(CALLBACK);
  });

  it("refreshes with a refresh token", () => {
    const form = new URLSearchParams({ grant_type: "refresh_token", refresh_token: "rt" });
    const res = buildTokenRequest(form, { ...cfg, clientSecret: secret });
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.body.get("refresh_token")).toBe("rt");
    expect(res.body.get("client_secret")).toBe(secret);
  });

  it.each(["client_credentials", "password", "urn:ietf:params:oauth:grant-type:device_code", ""])(
    "rejects grant_type %j so the secret is never spent on other flows",
    (grant) => {
      const res = buildTokenRequest(new URLSearchParams({ grant_type: grant }), { ...cfg, clientSecret: secret });
      expect(res.ok).toBe(false);
      if (res.ok) return;
      expect(res.error).toBe("unsupported_grant_type");
    }
  );

  it.each([
    ["code", undefined],
    ["code_verifier", undefined],
    ["redirect_uri", "https://evil.example/cb"],
    ["redirect_uri", undefined],
  ])("rejects a code exchange when %s is %j", (name, value) => {
    const form = new URLSearchParams({
      grant_type: "authorization_code",
      code: "c",
      redirect_uri: CALLBACK,
      code_verifier: "v",
    });
    if (value === undefined) form.delete(name);
    else form.set(name, value);
    const res = buildTokenRequest(form, { ...cfg, clientSecret: secret });
    expect(res.ok).toBe(false);
  });

  it("rejects a refresh without a refresh token", () => {
    const res = buildTokenRequest(new URLSearchParams({ grant_type: "refresh_token" }), { ...cfg, clientSecret: secret });
    expect(res.ok).toBe(false);
  });
});
