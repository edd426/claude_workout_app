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
