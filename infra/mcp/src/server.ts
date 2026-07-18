/**
 * ClaudeLifter workout MCP server — issue #79.
 *
 * v2: read-only, re-routed through the Azure Functions API with the shared
 * x-api-key auth (no more DefaultAzureCredential / Cosmos data-plane access).
 * Tool schemas and dispatch live in registry.ts so they can be unit-tested
 * without a stdio transport.
 *
 * Required environment variables: FUNCTIONS_BASE_URL, FUNCTIONS_API_KEY.
 * See infra/mcp/README.md for Claude Code / Claude Desktop configuration.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { TOOLS, handleToolCall } from "./registry.js";

const server = new Server(
  { name: "workout", version: "2.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const result = await handleToolCall(
    request.params.name,
    request.params.arguments
  );
  return { content: result.content, isError: result.isError };
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Server failed to start:", error);
  process.exit(1);
});
