/**
 * MCP tool registry — issue #79.
 *
 * Read-only ship: the server exposes 7 read tools + a health diagnostic.
 * All data access goes through the Azure Functions API (shared/http.ts).
 *
 * Write tools (create_template, update_template, delete_template,
 * create_program) are hard-disabled: the old direct-to-Cosmos write path
 * produced templates the iOS app could not resolve (invented exerciseIds,
 * DTO drift). They return a clear error until the write path is redesigned.
 *
 * search_exercises is likewise disabled: the app never syncs the exercise
 * library to the cloud, so the exercises container is empty and searches
 * would silently return nothing.
 */

import { listTemplates, getTemplate } from "./tools/templates.js";
import { listWorkouts, getWorkout } from "./tools/workouts.js";
import { getExerciseHistory } from "./tools/exercises.js";
import { getStats, getCalendar } from "./tools/stats.js";
import { health } from "./tools/health.js";

export interface ToolResult {
  content: { type: "text"; text: string }[];
  isError?: boolean;
}

export const TOOLS = [
  {
    name: "list_templates",
    description: "List all workout templates",
    inputSchema: { type: "object" as const, properties: {} },
  },
  {
    name: "get_template",
    description: "Get a workout template with its exercises",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: { type: "string", description: "Template ID" },
      },
      required: ["id"],
    },
  },
  {
    name: "list_workouts",
    description:
      "List workout session summaries with optional date filtering " +
      "(most recent first)",
    inputSchema: {
      type: "object" as const,
      properties: {
        startDate: { type: "string", description: "Start date (ISO 8601)" },
        endDate: { type: "string", description: "End date (ISO 8601)" },
        limit: {
          type: "number",
          description: "Max results (default: 50, capped at 200)",
        },
      },
    },
  },
  {
    name: "get_workout",
    description:
      "Get full detail of a specific workout session (exercises, sets, weights)",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: { type: "string", description: "Workout ID" },
      },
      required: ["id"],
    },
  },
  {
    name: "get_exercise_history",
    description:
      "Get historical sets for a specific exercise across past workouts",
    inputSchema: {
      type: "object" as const,
      properties: {
        exerciseId: { type: "string", description: "Exercise ID" },
        limit: {
          type: "number",
          description: "Max entries (default: 20, capped at 100)",
        },
      },
      required: ["exerciseId"],
    },
  },
  {
    name: "get_stats",
    description:
      "Get summary statistics: totals, personal records, workout frequency",
    inputSchema: {
      type: "object" as const,
      properties: {
        startDate: { type: "string", description: "Start date (ISO 8601)" },
        endDate: { type: "string", description: "End date (ISO 8601)" },
      },
    },
  },
  {
    name: "get_calendar",
    description:
      "Get per-day workout frequency data for a date range (calendar heatmap)",
    inputSchema: {
      type: "object" as const,
      properties: {
        startDate: { type: "string", description: "Start date (ISO 8601)" },
        endDate: { type: "string", description: "End date (ISO 8601)" },
      },
      required: ["startDate", "endDate"],
    },
  },
  {
    name: "health",
    description:
      "Diagnostic: check Functions API connectivity, auth status, and " +
      "configured base URL",
    inputSchema: { type: "object" as const, properties: {} },
  },
];

const DISABLED_WRITE_TOOLS = new Set([
  "create_template",
  "update_template",
  "delete_template",
  "create_program",
]);

const WRITE_DISABLED_MESSAGE =
  "This MCP server is read-only: write tools are disabled until the write " +
  "path is redesigned (issue #79). The previous direct-to-Cosmos writes " +
  "produced templates the iOS app could not resolve. Create or edit " +
  "templates in the ClaudeLifter app instead.";

const SEARCH_UNAVAILABLE_MESSAGE =
  "search_exercises is unavailable: the exercise library is not synced to " +
  "the cloud (the app bundles it locally), so the exercises container is " +
  "empty and searches would return misleading empty results. Browse " +
  "exercises in the ClaudeLifter app, or use get_exercise_history with a " +
  "known exerciseId. (issue #79)";

function textResult(value: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}

function errorResult(message: string): ToolResult {
  return { content: [{ type: "text", text: message }], isError: true };
}

function requireString(
  args: Record<string, unknown> | undefined,
  name: string
): string {
  const value = args?.[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Missing required argument: ${name}`);
  }
  return value;
}

function optionalNumber(
  args: Record<string, unknown> | undefined,
  name: string
): number | undefined {
  const value = args?.[name];
  return typeof value === "number" ? value : undefined;
}

function optionalString(
  args: Record<string, unknown> | undefined,
  name: string
): string | undefined {
  const value = args?.[name];
  return typeof value === "string" ? value : undefined;
}

export async function handleToolCall(
  name: string,
  args?: Record<string, unknown>
): Promise<ToolResult> {
  if (DISABLED_WRITE_TOOLS.has(name)) {
    return errorResult(WRITE_DISABLED_MESSAGE);
  }
  if (name === "search_exercises") {
    return errorResult(SEARCH_UNAVAILABLE_MESSAGE);
  }

  try {
    switch (name) {
      case "list_templates":
        return textResult(await listTemplates());

      case "get_template": {
        const id = requireString(args, "id");
        const template = await getTemplate(id);
        if (!template) return errorResult(`Template not found: ${id}`);
        return textResult(template);
      }

      case "list_workouts":
        return textResult(
          await listWorkouts({
            startDate: optionalString(args, "startDate"),
            endDate: optionalString(args, "endDate"),
            limit: optionalNumber(args, "limit"),
          })
        );

      case "get_workout": {
        const id = requireString(args, "id");
        const workout = await getWorkout(id);
        if (!workout) return errorResult(`Workout not found: ${id}`);
        return textResult(workout);
      }

      case "get_exercise_history": {
        const exerciseId = requireString(args, "exerciseId");
        return textResult(
          await getExerciseHistory(exerciseId, {
            limit: optionalNumber(args, "limit"),
          })
        );
      }

      case "get_stats":
        return textResult(
          await getStats({
            startDate: optionalString(args, "startDate"),
            endDate: optionalString(args, "endDate"),
          })
        );

      case "get_calendar": {
        const startDate = requireString(args, "startDate");
        const endDate = requireString(args, "endDate");
        return textResult(await getCalendar(startDate, endDate));
      }

      case "health":
        return textResult(await health());

      default:
        return errorResult(`Unknown tool: ${name}`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return errorResult(`Error: ${message}`);
  }
}
