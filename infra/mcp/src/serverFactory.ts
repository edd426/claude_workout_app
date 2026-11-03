/**
 * Builds the workout MCP server. Shared by the stdio entry point (server.ts,
 * Claude Code / Claude Desktop) and the remote Streamable HTTP endpoint
 * (azure/functions.ts, claude.ai connector — issue #162), so both expose
 * exactly the same tools.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { TOOLS, handleToolCall } from "./registry.js";

export function createWorkoutServer(): Server {
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

  return server;
}
