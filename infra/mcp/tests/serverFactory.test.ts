/**
 * The local (stdio) and remote (claude.ai) servers share one tool registry,
 * but only the local one may read files: attach_exercise_photo's imagePath.
 * These drive real MCP servers over the SDK's in-memory transport, so they
 * test the wiring, not just the tool function.
 */

import { describe, it, expect, vi, beforeAll, afterAll, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";

const mockApiGet = vi.fn();
const mockApiPost = vi.fn();

vi.mock("../src/shared/http.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../src/shared/http.js")>();
  return { ...actual, apiGet: mockApiGet, apiPost: mockApiPost };
});

const { createLocalServer, createWorkoutServer } = await import("../src/serverFactory.js");

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0xff, 0xd9]);
const mockFetch = vi.fn();
let dir: string;
let photo: string;

async function connect(server: Server): Promise<Client> {
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  const client = new Client({ name: "test", version: "1" });
  await client.connect(clientTransport);
  return client;
}

async function attachSchema(server: Server): Promise<Record<string, unknown>> {
  const client = await connect(server);
  const { tools } = await client.listTools();
  const tool = tools.find((candidate) => candidate.name === "attach_exercise_photo");
  return (tool?.inputSchema.properties ?? {}) as Record<string, unknown>;
}

async function attachByPath(server: Server) {
  const client = await connect(server);
  return client.callTool({
    name: "attach_exercise_photo",
    arguments: { externalId: "Leg_Extensions", imagePath: photo },
  });
}

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "server-factory-"));
  photo = join(dir, "machine.jpg");
  writeFileSync(photo, JPEG);
});

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

beforeEach(() => {
  mockApiGet.mockReset();
  mockApiPost.mockReset();
  mockApiGet.mockResolvedValue({
    sasUrl:
      "https://teststorage.blob.core.windows.net/workout-images/exercises/ext/Leg_Extensions.jpg?sig=x",
    expiresAt: "x",
  });
  mockApiPost.mockResolvedValue({ id: "op-1", op: "setExercisePhoto", status: "pending" });
  mockFetch.mockReset();
  mockFetch.mockImplementation(async () => new Response(null, { status: 201 }));
  vi.stubGlobal("fetch", mockFetch);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("local (stdio) server", () => {
  it("advertises imagePath", async () => {
    const properties = await attachSchema(createLocalServer());
    expect(properties).toHaveProperty("imagePath");
    expect(properties).toHaveProperty("imageBase64");
  });

  it("uploads a photo read from imagePath", async () => {
    const result = await attachByPath(createLocalServer());

    expect(result.isError).toBeFalsy();
    const [, init] = mockFetch.mock.calls[0] as [string, RequestInit];
    expect(Buffer.from(init.body as Uint8Array)).toEqual(JPEG);
    expect(mockApiPost).toHaveBeenCalledWith("inbox", {
      op: "setExercisePhoto",
      payload: { externalId: "Leg_Extensions", blobPath: "exercises/ext/Leg_Extensions.jpg" },
    });
  });
});

describe("remote (claude.ai) server", () => {
  it("does not advertise imagePath, only imageBase64", async () => {
    const properties = await attachSchema(createWorkoutServer());
    expect(properties).not.toHaveProperty("imagePath");
    expect(properties).toHaveProperty("imageBase64");
  });

  it("refuses imagePath with a clear message and reads nothing", async () => {
    const result = await attachByPath(createWorkoutServer());

    expect(result.isError).toBe(true);
    const [content] = result.content as { type: string; text: string }[];
    expect(content.text).toContain(
      "imagePath is only available on the local server; send imageBase64"
    );
    expect(mockFetch).not.toHaveBeenCalled();
    expect(mockApiPost).not.toHaveBeenCalled();
  });

  it("is the default: an explicit allowLocalFiles: false behaves the same", async () => {
    const result = await attachByPath(createWorkoutServer({ allowLocalFiles: false }));
    expect(result.isError).toBe(true);
  });
});
