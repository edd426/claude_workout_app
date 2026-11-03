/**
 * Builds the workout MCP server. Shared by the stdio entry point (server.ts,
 * Claude Code / Claude Desktop) and the remote Streamable HTTP endpoint
 * (azure/functions.ts, claude.ai connector — issue #162), so both expose
 * the same tools.
 *
 * One deliberate difference: only the local server may read local files
 * (attach_exercise_photo's imagePath). The remote server runs on Azure, where
 * a path would name a file on the Function host, so it neither advertises nor
 * accepts imagePath. Local file access is off unless asked for.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { handleToolCall, toolsFor } from "./registry.js";

export interface WorkoutServerOptions {
  /** Let attach_exercise_photo read imagePath. Local (stdio) server only. */
  allowLocalFiles?: boolean;
}

export function createWorkoutServer(options: WorkoutServerOptions = {}): Server {
  const allowLocalFiles = options.allowLocalFiles === true;
  const server = new Server(
    { name: "workout", version: "2.0.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: toolsFor({ allowLocalFiles }),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const result = await handleToolCall(
      request.params.name,
      request.params.arguments,
      { allowLocalFiles }
    );
    return { content: result.content, isError: result.isError };
  });

  return server;
}

/** The stdio server for Claude Code / Claude Desktop, on the user's machine. */
export function createLocalServer(): Server {
  return createWorkoutServer({ allowLocalFiles: true });
}
