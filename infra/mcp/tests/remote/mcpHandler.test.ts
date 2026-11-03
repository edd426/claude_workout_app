/** Tests for the authenticated Streamable HTTP /mcp handler — issue #162. */

import { describe, it, expect, vi } from "vitest";

import { handleMcpRequest, type McpHandlerDeps } from "../../src/remote/mcpHandler.js";
import { createWorkoutServer } from "../../src/serverFactory.js";

const RESOURCE_METADATA = "https://mcp.example/.well-known/oauth-protected-resource/mcp";
const OID = "99999999-8888-7777-6666-555555555555";

function deps(overrides: Partial<McpHandlerDeps> = {}): McpHandlerDeps {
  return {
    verify: vi.fn(async () => ({ oid: OID })),
    allowedOids: new Set([OID]),
    resourceMetadataUrl: RESOURCE_METADATA,
    createServer: createWorkoutServer,
    ...overrides,
  };
}

function rpc(method: string, id = 1, params: Record<string, unknown> = {}, auth?: string): Request {
  const headers: Record<string, string> = {
    "content-type": "application/json",
    accept: "application/json, text/event-stream",
  };
  if (auth !== undefined) headers.authorization = auth;
  return new Request("https://mcp.example/mcp", {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
  });
}

describe("authentication", () => {
  it("answers 401 with a resource_metadata challenge when no token is sent", async () => {
    const d = deps();
    const res = await handleMcpRequest(rpc("tools/list"), d);
    expect(res.status).toBe(401);
    const challenge = res.headers.get("www-authenticate") ?? "";
    expect(challenge).toMatch(/^Bearer /);
    expect(challenge).toContain(`resource_metadata="${RESOURCE_METADATA}"`);
    expect(d.verify).not.toHaveBeenCalled();
  });

  it("answers 401 for a non-Bearer authorization header", async () => {
    const res = await handleMcpRequest(rpc("tools/list", 1, {}, "Basic abc"), deps());
    expect(res.status).toBe(401);
  });

  it("answers 401 when the token fails verification, without echoing the reason", async () => {
    const d = deps({ verify: vi.fn(async () => { throw new Error("Token missing required scope: secret-detail"); }) });
    const res = await handleMcpRequest(rpc("tools/list", 1, {}, "Bearer bad"), d);
    expect(res.status).toBe(401);
    expect(await res.text()).not.toContain("secret-detail");
  });

  it("answers 403 for a valid token whose oid is not allowlisted", async () => {
    const d = deps({ verify: vi.fn(async () => ({ oid: "someone-else" })) });
    const res = await handleMcpRequest(rpc("tools/list", 1, {}, "Bearer ok"), d);
    expect(res.status).toBe(403);
  });

  it("fails closed with 403 when the allowlist is empty", async () => {
    const res = await handleMcpRequest(rpc("tools/list", 1, {}, "Bearer ok"), deps({ allowedOids: new Set() }));
    expect(res.status).toBe(403);
  });
});

describe("authorized requests", () => {
  it("serves initialize", async () => {
    const res = await handleMcpRequest(
      rpc("initialize", 1, {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "test", version: "1" },
      }, "Bearer ok"),
      deps()
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.result.serverInfo.name).toBe("workout");
    expect(body.result.capabilities.tools).toBeDefined();
  });

  it("lists the same tools as the stdio server", async () => {
    const res = await handleMcpRequest(rpc("tools/list", 2, {}, "Bearer ok"), deps());
    expect(res.status).toBe(200);
    const body = await res.json();
    const names = body.result.tools.map((t: { name: string }) => t.name);
    expect(names).toContain("list_templates");
    expect(names).toContain("health");
    expect(names).toContain("create_template");
  });

  it("passes the bearer token (without the scheme) to the verifier", async () => {
    const d = deps();
    await handleMcpRequest(rpc("tools/list", 3, {}, "Bearer the.jwt.value"), d);
    expect(d.verify).toHaveBeenCalledWith("the.jwt.value");
  });

  it("serves the 1.9.0 tools to claude.ai too", async () => {
    const res = await handleMcpRequest(rpc("tools/list", 4, {}, "Bearer ok"), deps());
    const body = await res.json();
    const names = body.result.tools.map((t: { name: string }) => t.name);
    for (const name of [
      "list_body_measurements",
      "list_medications",
      "list_medication_logs",
      "attach_exercise_photo",
    ]) {
      expect(names).toContain(name);
    }
  });
});

describe("request size (#170)", () => {
  // attach_exercise_photo takes the JPEG as base64: a photo at its 3.75 MB
  // limit is a ~5 MB request, over the SDK's 4 MiB default.
  function bigCall(base64Length: number): Request {
    return rpc(
      "tools/call",
      5,
      { name: "does_not_exist", arguments: { imageBase64: "A".repeat(base64Length) } },
      "Bearer ok"
    );
  }

  it("accepts a request carrying a photo at the tool's 3.75 MB limit", async () => {
    const res = await handleMcpRequest(bigCall(5_000_000), deps());
    expect(res.status).toBe(200);
    const body = await res.json();
    // Reached the tool dispatcher: the body was read, not refused with 413.
    expect(body.result.isError).toBe(true);
    expect(body.result.content[0].text).toContain("Unknown tool");
  });

  it("still refuses a request far beyond any photo", async () => {
    const res = await handleMcpRequest(bigCall(7 * 1024 * 1024), deps());
    expect(res.status).toBe(413);
  });

  it("a large body does not get past a failed token check", async () => {
    const d = deps({ verify: vi.fn(async () => { throw new Error("bad"); }) });
    const res = await handleMcpRequest(bigCall(5_000_000), d);
    expect(res.status).toBe(401);
  });
});
