import {
  app,
  HttpRequest,
  HttpResponseInit,
  InvocationContext,
} from "@azure/functions";
import Anthropic from "@anthropic-ai/sdk";
import { authenticate } from "../shared/auth";
import { InsightsRequest, InsightsResponse, Insight } from "../shared/types";

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

const INSIGHTS_SYSTEM_PROMPT = `You are an expert personal trainer analyzing workout data. Generate 1-3 brief, actionable insights based on the recent workout summary provided.

Each insight should be one of these types:
- "suggestion": Actionable advice to improve training
- "warning": Something the user should be aware of (e.g., muscle imbalance, overtraining)
- "encouragement": Positive reinforcement of good habits or progress

Respond ONLY with a JSON array of objects, each with "content" (string) and "type" (one of: "suggestion", "warning", "encouragement"). No other text.

Example response:
[
  {"content": "You haven't trained legs in 12 days. Consider adding a leg session this week.", "type": "warning"},
  {"content": "Your bench press has gone up 5kg over the last month — nice progression!", "type": "encouragement"}
]`;

app.http("insights", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "insights",
  handler: async (
    request: HttpRequest,
    context: InvocationContext
  ): Promise<HttpResponseInit> => {
    const authError = authenticate(request);
    if (authError) return authError;

    let body: InsightsRequest;
    try {
      body = (await request.json()) as InsightsRequest;
    } catch {
      return {
        status: 400,
        jsonBody: { error: "Invalid JSON body" },
      };
    }

    if (!body.recentWorkoutSummary) {
      return {
        status: 400,
        jsonBody: { error: "Missing required field: recentWorkoutSummary" },
      };
    }

    try {
      const client = getAnthropicClient();

      let userMessage = `Here is my recent workout summary:\n\n${body.recentWorkoutSummary}`;
      if (body.lastInsightDate) {
        userMessage += `\n\nLast insights were generated on: ${body.lastInsightDate}`;
      }

      const response = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        system: INSIGHTS_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userMessage }],
      });

      const textContent = response.content.find((c) => c.type === "text");
      if (!textContent || textContent.type !== "text") {
        throw new Error("No text content in Anthropic response");
      }

      const insights: Insight[] = JSON.parse(textContent.text);

      const result: InsightsResponse = { insights };
      return { jsonBody: result };
    } catch (error) {
      context.error("Insights generation failed:", error);
      return {
        status: 500,
        jsonBody: { error: "Failed to generate insights" },
      };
    }
  },
});
