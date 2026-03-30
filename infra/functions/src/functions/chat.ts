import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import Anthropic from "@anthropic-ai/sdk";
import { authenticate } from "../shared/auth";
import { ChatRequest } from "../shared/types";

let anthropicClient: Anthropic | null = null;

function getAnthropicClient(): Anthropic {
  if (!anthropicClient) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error("ANTHROPIC_API_KEY not configured");
    }
    anthropicClient = new Anthropic({ apiKey });
  }
  return anthropicClient;
}

app.http("chat", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "chat",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: ChatRequest;
    try {
      body = (await request.json()) as ChatRequest;
    } catch {
      return {
        status: 400,
        jsonBody: { error: "Invalid JSON body" },
      };
    }

    if (!body.messages || body.messages.length === 0) {
      return {
        status: 400,
        jsonBody: { error: "Missing required field: messages" },
      };
    }

    const model =
      body.model || process.env.ANTHROPIC_MODEL_DEFAULT || "claude-haiku-4-5-20251001";
    const maxTokens = body.max_tokens || 4096;

    try {
      const client = getAnthropicClient();

      if (body.stream) {
        // Stream SSE response back to client
        const stream = await client.messages.stream({
          model,
          max_tokens: maxTokens,
          messages: body.messages as Anthropic.MessageParam[],
          system: body.system as string | Anthropic.TextBlockParam[] | undefined,
          tools: body.tools as Anthropic.Tool[] | undefined,
        });

        const encoder = new TextEncoder();
        const readableStream = new ReadableStream({
          async start(controller) {
            try {
              for await (const event of stream) {
                const sseData = `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`;
                controller.enqueue(encoder.encode(sseData));
              }
              controller.enqueue(encoder.encode("event: done\ndata: [DONE]\n\n"));
              controller.close();
            } catch (error) {
              context.error("Stream error:", error);
              controller.error(error);
            }
          },
        });

        return {
          status: 200,
          headers: {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
          },
          body: readableStream,
        };
      } else {
        // Non-streaming response
        const response = await client.messages.create({
          model,
          max_tokens: maxTokens,
          messages: body.messages as Anthropic.MessageParam[],
          system: body.system as string | Anthropic.TextBlockParam[] | undefined,
          tools: body.tools as Anthropic.Tool[] | undefined,
        });

        return { jsonBody: response };
      }
    } catch (error) {
      context.error("Chat proxy error:", error);
      const statusCode =
        error instanceof Anthropic.APIError ? error.status : 500;
      return {
        status: statusCode,
        jsonBody: {
          error: "Chat request failed",
          detail: error instanceof Error ? error.message : "Unknown error",
        },
      };
    }
  },
});
