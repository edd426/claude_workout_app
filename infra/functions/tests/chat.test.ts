/**
 * Tests for chat Azure Function — issue #48
 *
 * #48: thinking_budget sent by client was silently dropped.
 *      Fix: pass thinking parameter to Anthropic SDK when present.
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { mockMessagesCreate, mockMessagesStream } from "./__mocks__/@anthropic-ai/sdk";
import "../src/functions/chat";

// `app` is the mock stub from moduleNameMapper; chat.ts also imported the same
// stub, so app.http.mock.calls is already populated.
const mockApp = app as unknown as { http: jest.Mock };

type Handler = (req: unknown, ctx: InvocationContext) => Promise<{ status?: number; jsonBody?: unknown }>;

let handler: Handler;

beforeAll(() => {
  process.env.ANTHROPIC_API_KEY = "test-anthropic-key";
  const call = mockApp.http.mock.calls.find(([name]: [string]) => name === "chat");
  if (!call) throw new Error("chat handler was not registered with app.http()");
  handler = call[1].handler;
});

function makeRequest(body: unknown, apiKey = "test-key") {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(body, { "x-api-key": apiKey });
}

function makeContext() {
  return new InvocationContext();
}

// ─── Issue #48 RED tests ────────────────────────────────────────────────────

describe("chat — issue #48: thinking_budget forwarded to Anthropic", () => {
  beforeEach(() => {
    mockMessagesCreate.mockClear();
    mockMessagesStream.mockClear();
  });

  test("non-streaming: includes thinking parameter when thinking_budget is provided", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "Help me plan a workout" }],
      thinking_budget: 10000,
      stream: false,
    });
    await handler(req, makeContext());

    expect(mockMessagesCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        thinking: { type: "enabled", budget_tokens: 10000 },
      })
    );
  });

  test("non-streaming: max_tokens is at least thinking_budget + 4096", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "Plan my week" }],
      thinking_budget: 8000,
      max_tokens: 1024,
      stream: false,
    });
    await handler(req, makeContext());

    const callArgs = mockMessagesCreate.mock.calls[0][0];
    expect(callArgs.max_tokens).toBeGreaterThanOrEqual(8000 + 4096);
  });

  test("non-streaming: does NOT include thinking parameter when thinking_budget is absent", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "Quick question" }],
      stream: false,
    });
    await handler(req, makeContext());

    const callArgs = mockMessagesCreate.mock.calls[0][0];
    expect(callArgs.thinking).toBeUndefined();
  });

  test("streaming: includes thinking parameter when thinking_budget is provided", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "Coach me" }],
      thinking_budget: 12000,
      stream: true,
    });
    await handler(req, makeContext());

    expect(mockMessagesStream).toHaveBeenCalledWith(
      expect.objectContaining({
        thinking: { type: "enabled", budget_tokens: 12000 },
      })
    );
  });

  test("streaming: max_tokens is at least thinking_budget + 4096", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "Build me a program" }],
      thinking_budget: 16000,
      max_tokens: 2048,
      stream: true,
    });
    await handler(req, makeContext());

    const callArgs = mockMessagesStream.mock.calls[0][0];
    expect(callArgs.max_tokens).toBeGreaterThanOrEqual(16000 + 4096);
  });

  test("streaming: does NOT include thinking parameter when thinking_budget is absent", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "What exercises for chest?" }],
      stream: true,
    });
    await handler(req, makeContext());

    const callArgs = mockMessagesStream.mock.calls[0][0];
    expect(callArgs.thinking).toBeUndefined();
  });
});

// ─── Issue #90: model / max_tokens guardrails ──────────────────────────────

describe("chat — issue #90: model and max_tokens guardrails", () => {
  beforeEach(() => {
    mockMessagesCreate.mockClear();
    mockMessagesStream.mockClear();
    delete process.env.ALLOWED_MODELS;
    delete process.env.MAX_TOKENS_CAP;
  });

  test("rejects a disallowed model with 400 before calling Anthropic", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      model: "claude-opus-4-1-most-expensive",
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBe(400);
    expect(mockMessagesCreate).not.toHaveBeenCalled();
  });

  test("allows a known model", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      model: "claude-sonnet-4-6",
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBeUndefined();
    expect(mockMessagesCreate).toHaveBeenCalled();
  });

  test("rejects oversize max_tokens with 400 before calling Anthropic", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      max_tokens: 999999,
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBe(400);
    expect(mockMessagesCreate).not.toHaveBeenCalled();
  });

  test("allows max_tokens within the default cap", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      max_tokens: 4096,
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBeUndefined();
    expect(mockMessagesCreate).toHaveBeenCalled();
  });

  test("rejects a thinking_budget that would push max_tokens past the cap", async () => {
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      thinking_budget: 100000,
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBe(400);
    expect(mockMessagesCreate).not.toHaveBeenCalled();
  });

  test("MAX_TOKENS_CAP env var overrides the default cap", async () => {
    process.env.MAX_TOKENS_CAP = "1000";
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      max_tokens: 2000,
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBe(400);
    expect(mockMessagesCreate).not.toHaveBeenCalled();
  });

  test("ALLOWED_MODELS env var overrides the default allowlist", async () => {
    process.env.ALLOWED_MODELS = "custom-model-a,custom-model-b";
    const req = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      model: "custom-model-a",
      stream: false,
    });
    const result = await handler(req, makeContext());

    expect(result.status).toBeUndefined();
    expect(mockMessagesCreate).toHaveBeenCalled();

    // and the previously-default model is now rejected
    mockMessagesCreate.mockClear();
    const req2 = makeRequest({
      messages: [{ role: "user", content: "hi" }],
      model: "claude-sonnet-4-6",
      stream: false,
    });
    const result2 = await handler(req2, makeContext());
    expect(result2.status).toBe(400);
    expect(mockMessagesCreate).not.toHaveBeenCalled();
  });
});
