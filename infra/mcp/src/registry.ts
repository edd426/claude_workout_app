/** MCP tool registry. Reads and durable inbox writes use the Functions API. */

import { listTemplates, getTemplate } from "./tools/templates.js";
import { listWorkouts, getWorkout } from "./tools/workouts.js";
import { getExerciseHistory } from "./tools/exercises.js";
import { getStats, getCalendar } from "./tools/stats.js";
import { health } from "./tools/health.js";
import { searchExercises } from "./tools/catalog.js";
import {
  createCustomExercise,
  createProgram,
  createTemplate,
  deleteTemplate,
  listPendingWrites,
  updateTemplate,
} from "./tools/writes.js";

export interface ToolResult {
  content: { type: "text"; text: string }[];
  isError?: boolean;
}

const templateExerciseSchema = {
  type: "object" as const,
  properties: {
    externalId: {
      type: "string",
      description:
        "Stable external ID returned by search_exercises; never invent one",
    },
    order: { type: "integer", minimum: 0 },
    defaultSets: { type: "integer", minimum: 1 },
    defaultReps: { type: "integer", minimum: 1 },
    defaultWeight: { type: "number" },
    defaultRestSeconds: { type: "integer", minimum: 0 },
    notes: { type: "string" },
  },
  required: ["externalId", "order", "defaultSets", "defaultReps"],
};

const createTemplateProperties = {
  name: { type: "string", description: "Template name" },
  notes: { type: "string", description: "Optional template notes" },
  exercises: {
    type: "array",
    items: templateExerciseSchema,
    description: "Ordered exercises using exact externalId values",
  },
};

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
  {
    name: "search_exercises",
    description:
      "Search the bundled exercise catalog and synced custom exercises by name",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "Exercise name or partial name",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "create_template",
    description:
      "Validate exercise externalIds and enqueue a template for the app",
    inputSchema: {
      type: "object" as const,
      properties: createTemplateProperties,
      required: ["name", "exercises"],
    },
  },
  {
    name: "update_template",
    description:
      "Validate any exercise externalIds and enqueue a template update for approval",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: { type: "string", description: "Template UUID" },
        name: { type: "string" },
        notes: { type: "string" },
        exercises: {
          type: "array",
          items: templateExerciseSchema,
          description: "Replacement exercise list",
        },
      },
      required: ["id"],
    },
  },
  {
    name: "delete_template",
    description: "Enqueue a template deletion for approval",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: { type: "string", description: "Template UUID" },
        name: {
          type: "string",
          description: "Template name shown in the approval prompt",
        },
      },
      required: ["id", "name"],
    },
  },
  {
    name: "create_program",
    description:
      "Validate all templates first, then enqueue each template creation",
    inputSchema: {
      type: "object" as const,
      properties: {
        templates: {
          type: "array",
          items: {
            type: "object",
            properties: createTemplateProperties,
            required: ["name", "exercises"],
          },
        },
      },
      required: ["templates"],
    },
  },
  {
    name: "create_custom_exercise",
    description: "Enqueue creation of a custom exercise on the app",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: { type: "string" },
        equipment: { type: "string" },
        primaryMuscles: { type: "array", items: { type: "string" } },
        secondaryMuscles: { type: "array", items: { type: "string" } },
        instructions: { type: "array", items: { type: "string" } },
        notes: { type: "string" },
      },
      required: ["name"],
    },
  },
  {
    name: "list_pending_writes",
    description:
      "List inbox operations by status, including failures and their errors",
    inputSchema: {
      type: "object" as const,
      properties: {
        status: {
          type: "string",
          enum: [
            "pending",
            "awaitingApproval",
            "applied",
            "rejected",
            "failed",
          ],
          description: "Defaults to pending",
        },
      },
    },
  },
];

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

      case "search_exercises":
        return textResult(
          await searchExercises(requireString(args, "query"))
        );

      case "create_template":
        return textResult(await createTemplate(args));

      case "update_template":
        return textResult(await updateTemplate(args));

      case "delete_template":
        return textResult(await deleteTemplate(args));

      case "create_program":
        return textResult(await createProgram(args));

      case "create_custom_exercise":
        return textResult(await createCustomExercise(args));

      case "list_pending_writes":
        return textResult(
          await listPendingWrites({
            status: optionalString(args, "status"),
          })
        );

      default:
        return errorResult(`Unknown tool: ${name}`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return errorResult(`Error: ${message}`);
  }
}
