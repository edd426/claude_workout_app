/** Tests for the Azure Functions <-> Fetch API adapters — issue #162. */

import { describe, it, expect } from "vitest";

import { toWebRequest, toHttpResponse } from "../../src/remote/adapters.js";

function fakeAzureRequest(method: string, body?: string) {
  const encoded = new TextEncoder().encode(body ?? "");
  return {
    method,
    url: "https://mcp.example/mcp?x=1",
    headers: new Headers({ "content-type": "application/json", authorization: "Bearer t" }),
    arrayBuffer: async () => encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength),
  };
}

describe("toWebRequest", () => {
  it("carries method, url, headers and body", async () => {
    const req = await toWebRequest(fakeAzureRequest("POST", '{"a":1}'));
    expect(req.method).toBe("POST");
    expect(req.url).toBe("https://mcp.example/mcp?x=1");
    expect(req.headers.get("authorization")).toBe("Bearer t");
    expect(await req.json()).toEqual({ a: 1 });
  });

  it("sends no body for GET", async () => {
    const req = await toWebRequest(fakeAzureRequest("GET"));
    expect(req.method).toBe("GET");
    expect(req.body).toBeNull();
  });
});

describe("toHttpResponse", () => {
  it("copies status, headers and body text", async () => {
    const res = await toHttpResponse(
      new Response('{"ok":true}', { status: 201, headers: { "content-type": "application/json", "x-y": "z" } })
    );
    expect(res.status).toBe(201);
    expect(res.headers).toMatchObject({ "content-type": "application/json", "x-y": "z" });
    expect(res.body).toBe('{"ok":true}');
  });
});
