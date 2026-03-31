import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import {
  listTemplates,
  getTemplate,
  createTemplate,
  updateTemplate,
  deleteTemplate,
} from "./tools/templates.js";
import { listWorkouts, getWorkout } from "./tools/workouts.js";
import { searchExercises, getExerciseHistory } from "./tools/exercises.js";
import { getStats, getCalendar } from "./tools/stats.js";
import { createProgram } from "./tools/programs.js";

const server = new Server(
  { name: "workout", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

const TOOLS = [
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
    name: "create_template",
    description: "Create a new workout template",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: { type: "string", description: "Template name" },
        notes: { type: "string", description: "Optional notes" },
        exercises: {
          type: "array",
          description: "List of exercises with defaults",
          items: {
            type: "object",
            properties: {
              id: { type: "string" },
              exerciseId: { type: "string", description: "Exercise ID from the library" },
              exerciseName: { type: "string", description: "Exercise name" },
              defaultSets: { type: "number", description: "Number of sets" },
              defaultReps: { type: "number", description: "Reps per set" },
              defaultWeight: { type: "number", description: "Weight (optional)" },
              defaultRestSeconds: { type: "number", description: "Rest between sets in seconds (default: 90)" },
              notes: { type: "string", description: "Optional notes" },
            },
            required: ["id", "exerciseId", "exerciseName", "defaultSets", "defaultReps"],
          },
        },
      },
      required: ["name", "exercises"],
    },
  },
  {
    name: "update_template",
    description: "Update an existing workout template",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: { type: "string", description: "Template ID" },
        name: { type: "string", description: "New name" },
        notes: { type: "string", description: "New notes" },
        exercises: {
          type: "array",
          description: "Updated exercise list",
          items: {
            type: "object",
            properties: {
              id: { type: "string" },
              exerciseId: { type: "string" },
              exerciseName: { type: "string" },
              defaultSets: { type: "number" },
              defaultReps: { type: "number" },
              defaultWeight: { type: "number" },
              defaultRestSeconds: { type: "number" },
              notes: { type: "string" },
            },
            required: ["id", "exerciseId", "exerciseName", "defaultSets", "defaultReps"],
          },
        },
      },
      required: ["id"],
    },
  },
  {
    name: "delete_template",
    description: "Delete a workout template",
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
    description: "List workout sessions with optional date filtering",
    inputSchema: {
      type: "object" as const,
      properties: {
        startDate: { type: "string", description: "Start date (ISO 8601)" },
        endDate: { type: "string", description: "End date (ISO 8601)" },
        limit: { type: "number", description: "Max results (default: 50)" },
      },
    },
  },
  {
    name: "get_workout",
    description: "Get full detail of a specific workout session",
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
    description: "Get historical data for a specific exercise across workouts",
    inputSchema: {
      type: "object" as const,
      properties: {
        exerciseId: { type: "string", description: "Exercise ID" },
        limit: { type: "number", description: "Max entries (default: 20)" },
      },
      required: ["exerciseId"],
    },
  },
  {
    name: "search_exercises",
    description: "Search exercises by name, muscle group, or equipment",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: { type: "string", description: "Search by exercise name (partial match)" },
        muscle: { type: "string", description: "Filter by primary muscle group" },
        equipment: { type: "string", description: "Filter by equipment type" },
        limit: { type: "number", description: "Max results (default: 50)" },
      },
    },
  },
  {
    name: "get_stats",
    description: "Get summary statistics including PRs, volume, and workout frequency",
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
    description: "Get workout frequency data for a date range (for calendar heatmap)",
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
    name: "create_program",
    description: "Create a multi-day training program (multiple templates)",
    inputSchema: {
      type: "object" as const,
      properties: {
        name: { type: "string", description: "Program name" },
        templates: {
          type: "array",
          description: "List of templates to create",
          items: {
            type: "object",
            properties: {
              name: { type: "string", description: "Template/day name (e.g., 'Push Day')" },
              notes: { type: "string" },
              exercises: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    id: { type: "string" },
                    exerciseId: { type: "string" },
                    exerciseName: { type: "string" },
                    defaultSets: { type: "number" },
                    defaultReps: { type: "number" },
                    defaultWeight: { type: "number" },
                    defaultRestSeconds: { type: "number" },
                    notes: { type: "string" },
                  },
                  required: ["id", "exerciseId", "exerciseName", "defaultSets", "defaultReps"],
                },
              },
            },
            required: ["name", "exercises"],
          },
        },
      },
      required: ["name", "templates"],
    },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    let result: unknown;

    switch (name) {
      case "list_templates":
        result = await listTemplates();
        break;

      case "get_template":
        result = await getTemplate(args!.id as string);
        if (!result) {
          return { content: [{ type: "text", text: `Template not found: ${args!.id}` }], isError: true };
        }
        break;

      case "create_template":
        result = await createTemplate(
          args!.name as string,
          args!.exercises as Parameters<typeof createTemplate>[1],
          args!.notes as string | undefined,
        );
        break;

      case "update_template":
        result = await updateTemplate(args!.id as string, {
          name: args!.name as string | undefined,
          notes: args!.notes as string | undefined,
          exercises: args!.exercises as Parameters<typeof updateTemplate>[1]["exercises"],
        });
        if (!result) {
          return { content: [{ type: "text", text: `Template not found: ${args!.id}` }], isError: true };
        }
        break;

      case "delete_template":
        const deleted = await deleteTemplate(args!.id as string);
        result = deleted
          ? { success: true, message: "Template deleted" }
          : { success: false, message: "Template not found" };
        if (!deleted) {
          return { content: [{ type: "text", text: `Template not found: ${args!.id}` }], isError: true };
        }
        break;

      case "list_workouts":
        result = await listWorkouts({
          startDate: args?.startDate as string | undefined,
          endDate: args?.endDate as string | undefined,
          limit: args?.limit as number | undefined,
        });
        break;

      case "get_workout":
        result = await getWorkout(args!.id as string);
        if (!result) {
          return { content: [{ type: "text", text: `Workout not found: ${args!.id}` }], isError: true };
        }
        break;

      case "get_exercise_history":
        result = await getExerciseHistory(args!.exerciseId as string, {
          limit: args?.limit as number | undefined,
        });
        break;

      case "search_exercises":
        result = await searchExercises({
          name: args?.name as string | undefined,
          muscle: args?.muscle as string | undefined,
          equipment: args?.equipment as string | undefined,
          limit: args?.limit as number | undefined,
        });
        break;

      case "get_stats":
        result = await getStats({
          startDate: args?.startDate as string | undefined,
          endDate: args?.endDate as string | undefined,
        });
        break;

      case "get_calendar":
        result = await getCalendar(
          args!.startDate as string,
          args!.endDate as string,
        );
        break;

      case "create_program":
        result = await createProgram(
          args!.name as string,
          args!.templates as Parameters<typeof createProgram>[1],
        );
        break;

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }

    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [{ type: "text", text: `Error: ${message}` }],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Server failed to start:", error);
  process.exit(1);
});
