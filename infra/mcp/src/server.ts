/**
 * ClaudeLifter workout MCP server — issue #79.
 *
 * Reads and durable inbox writes are routed through the Azure Functions API
 * with shared x-api-key auth. Tool schemas and dispatch live in registry.ts
 * so they can be unit-tested without a stdio transport.
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
import { buildFreshness } from "./shared/build-info.js";

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
  // #138: warn on stderr before serving a single request. This is the only
  // check that runs on the real launch path — `node dist/src/server.js` runs
  // no npm lifecycle script, and dist/ is gitignored so CI has nothing to
  // diff. Warn rather than exit: a stale server that still answers is far
  // better than an MCP client that cannot start at all, and the warning is
  // visible in the client's server log.
  const freshness = await buildFreshness();
  if (freshness.stale) {
    console.error(`workout-mcp: STALE BUILD — ${freshness.staleReason}`);
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Server failed to start:", error);
  process.exit(1);
});
