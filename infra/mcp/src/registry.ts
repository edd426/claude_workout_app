/** MCP tool registry. Reads and durable inbox writes use the Functions API. */

import { listTemplates, getTemplate } from "./tools/templates.js";
import { listWorkouts, getWorkout } from "./tools/workouts.js";
import { getExerciseHistory } from "./tools/exercises.js";
import { getStats, getCalendar } from "./tools/stats.js";
import { health } from "./tools/health.js";
import { searchExercises } from "./tools/catalog.js";
import {
  getReportPhoto,
  listExerciseReports,
  resolveExerciseReport,
} from "./tools/reports.js";
import { listBodyMeasurements, MEASUREMENT_SITES } from "./tools/bodyMeasurements.js";
import { listMedicationLogs, listMedications } from "./tools/medications.js";
import { attachExercisePhoto } from "./tools/exercisePhotos.js";
import {
  createCustomExercise,
  createProgram,
  createTemplate,
  deleteInboxOperation,
  deleteTemplate,
  listPendingWrites,
  updateTemplate,
} from "./tools/writes.js";

export type ToolContent =
  | { type: "text"; text: string }
  | { type: "image"; data: string; mimeType: string };

export interface ToolResult {
  content: ToolContent[];
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
    alternatives: {
      type: "array",
      description:
        "Substitutes for this slot when the machine is taken, in preference " +
        "order; the app offers them as a one-tap swap for that session only. " +
        "Each externalId is validated like the main exercise's. Omit to keep " +
        "the slot's current alternatives (update_template), [] clears them, " +
        "a list replaces them. Never null.",
      items: {
        type: "object",
        properties: {
          externalId: {
            type: "string",
            description: "Exact externalId from search_exercises",
          },
          note: {
            type: "string",
            description: 'When to use it, e.g. "if the rack is taken"',
          },
        },
        required: ["externalId"],
      },
    },
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

const ATTACH_PHOTO_DESCRIPTION =
  "Attach a JPEG photo (e.g. the gym's actual machine) to an exercise, " +
  "so its card in the app shows it. Validates the exercise exists, " +
  "uploads the image to blob storage, then queues a setExercisePhoto " +
  "inbox operation that needs approval on the phone: nothing changes " +
  "until it is approved there, and one batch approval covers many " +
  "photos. Attaching again replaces the exercise's photo. JPEG only, " +
  "at most 3.75 MB.";

const ATTACH_PHOTO_EXTERNAL_ID = {
  type: "string",
  description: "Exact externalId from search_exercises (catalog or custom:)",
};

const ATTACH_PHOTO_BASE64 = {
  type: "string",
  description:
    "The JPEG, base64-encoded (a data:image/jpeg;base64, prefix is accepted)",
};

/**
 * attach_exercise_photo as the remote (claude.ai) server lists it: no
 * imagePath, which it refuses anyway, so the model is not offered it.
 */
const REMOTE_ATTACH_PHOTO_TOOL = {
  name: "attach_exercise_photo",
  description: ATTACH_PHOTO_DESCRIPTION + " Send the JPEG as imageBase64.",
  inputSchema: {
    type: "object" as const,
    properties: {
      externalId: ATTACH_PHOTO_EXTERNAL_ID,
      imageBase64: ATTACH_PHOTO_BASE64,
    },
    required: ["externalId", "imageBase64"],
  },
};

export interface ToolCallOptions {
  /** True only for the local (stdio) server: attach_exercise_photo may read imagePath. */
  allowLocalFiles?: boolean;
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
    name: "list_exercise_reports",
    description:
      "Read the complaint backlog filed from the app: mislabeled exercises, " +
      "swap requests, app bugs, bad data. Each report carries the context " +
      "captured when it was filed (exercise externalId, workout, set state, " +
      "app version). Defaults to everything not yet resolved. A non-null " +
      "photoURL means a photo is attached; view it with get_report_photo.",
    inputSchema: {
      type: "object" as const,
      properties: {
        status: {
          type: "string",
          enum: ["open", "acknowledged", "resolved", "all"],
          description: "Defaults to open + acknowledged (the live backlog)",
        },
        category: {
          type: "string",
          enum: [
            "bug",
            "swapRequest",
            "wrongExercise",
            "dataError",
            "formOrSetup",
            "other",
          ],
        },
        exerciseExternalId: {
          type: "string",
          description: "Filter to reports about one exercise",
        },
        limit: {
          type: "number",
          description: "Max results (default: 100, capped at 500)",
        },
      },
    },
  },
  {
    name: "get_report_photo",
    description:
      "View the photo attached to an exercise report — a screenshot of a " +
      "bug, or a picture of the machine a report is about. Returns a short " +
      "description of the report and the photo itself. A report whose " +
      "photoURL is null has no photo, or one that has not uploaded yet: the " +
      "phone uploads on its next sync with connectivity, and the gym is " +
      "often offline.",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: {
          type: "string",
          description: "Report UUID, from list_exercise_reports",
        },
      },
      required: ["id"],
    },
  },
  {
    name: "resolve_exercise_report",
    description:
      "Set a report's status, so the backlog reflects reality. Use " +
      "'acknowledged' when the work is known but not done (an issue was " +
      "filed, or a fix is written but not installed), 'resolved' when it is " +
      "finished, and 'open' to reopen one that was closed too early — a fix " +
      "that turns out not to work must be able to come back. Pass 'ids' to " +
      "answer several at once. Enqueues inbox operations: the change lands " +
      "when the phone next syncs.",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: { type: "string", description: "Report UUID. Use this or ids." },
        ids: {
          type: "array",
          items: { type: "string" },
          description:
            "Several report UUIDs, all set to the same status. Every id is " +
            "validated before any is enqueued.",
        },
        status: {
          type: "string",
          enum: ["resolved", "acknowledged", "open"],
          description: "Defaults to resolved",
        },
        resolution: {
          type: "string",
          description: "What was done — shown next to the report in the app",
        },
      },
    },
  },
  {
    name: "attach_exercise_photo",
    description:
      ATTACH_PHOTO_DESCRIPTION +
      " Pass exactly one of imagePath (an absolute path to a local .jpg or " +
      ".jpeg file; the local server only, and the cheaper choice for many " +
      "photos) or imageBase64.",
    inputSchema: {
      type: "object" as const,
      properties: {
        externalId: ATTACH_PHOTO_EXTERNAL_ID,
        imageBase64: ATTACH_PHOTO_BASE64,
        imagePath: {
          type: "string",
          description:
            "Absolute path to a local .jpg/.jpeg file (symlinks are resolved). " +
            "Local server only",
        },
      },
      required: ["externalId"],
    },
  },
  {
    name: "list_body_measurements",
    description:
      "Read body measurements (circumference, cm) logged in the app, newest " +
      "first, with the stored height and the current waist-to-height ratio " +
      "banded per NICE NG246 (< 0.5 healthy, 0.5–0.59 increased risk, ≥ 0.6 " +
      "high risk). The ratio always uses the latest waist measurement, " +
      "whatever the filters. mirrored: false means the phone has not synced " +
      "this data yet, which is not the same as having none.",
    inputSchema: {
      type: "object" as const,
      properties: {
        site: {
          type: "string",
          enum: [...MEASUREMENT_SITES],
          description: "Only this site (the app logs waist today)",
        },
        startDate: { type: "string", description: "From (ISO 8601, UTC)" },
        endDate: {
          type: "string",
          description: "To (ISO 8601, UTC); a date alone includes that whole day",
        },
        limit: {
          type: "number",
          description: "Max results (default: 100, capped at 500)",
        },
      },
    },
  },
  {
    name: "list_medications",
    description:
      "List the medications defined in the app's medication log: name, dose " +
      "form (mass/tablet/liquid/units), tablet strength, and concentration " +
      "(direct mg/mL, or vial mg ÷ diluent mL). Archived medications are " +
      "excluded unless includeArchived is true. Read-only. mirrored: false " +
      "means the phone has not synced this data yet.",
    inputSchema: {
      type: "object" as const,
      properties: {
        includeArchived: {
          type: "boolean",
          description: "Include archived medications (default false)",
        },
      },
    },
  },
  {
    name: "list_medication_logs",
    description:
      "List logged medication doses, newest first, each with its medication's " +
      "name, the amount and unit as entered, and computedMg. computedMg, " +
      "concentrationMgPerMlAtLog and tabletStrengthMgAtLog are as logged: " +
      "never recompute a past dose from the medication's current " +
      "concentration or tablet strength (a re-mixed vial or a new strength " +
      "does not change history). computedMg is absent where it cannot be " +
      "computed (IU, or mL with no known concentration). Read-only.",
    inputSchema: {
      type: "object" as const,
      properties: {
        medicationId: {
          type: "string",
          description: "Only this medication (id from list_medications)",
        },
        startDate: { type: "string", description: "From (ISO 8601, UTC)" },
        endDate: {
          type: "string",
          description: "To (ISO 8601, UTC); a date alone includes that whole day",
        },
        limit: {
          type: "number",
          description: "Max results (default: 100, capped at 500)",
        },
      },
    },
  },
  {
    name: "delete_inbox_operation",
    description:
      "Permanently delete one or more terminal inbox operations (applied, " +
      "rejected, or failed) so the backlog seen by list_pending_writes stops " +
      "growing. Refused with an error for pending/awaitingApproval operations " +
      "— the phone may not have fetched those yet, and deleting unseen work " +
      "would make it disappear silently. Pass 'ids' to clear several at once.",
    inputSchema: {
      type: "object" as const,
      properties: {
        id: {
          type: "string",
          description: "Inbox operation UUID. Use this or ids.",
        },
        ids: {
          type: "array",
          items: { type: "string" },
          description:
            "Several inbox operation UUIDs. Every id is validated before " +
            "any is deleted.",
        },
      },
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

/** The tool list a server advertises: the remote one omits imagePath. */
export function toolsFor(options: ToolCallOptions = {}) {
  if (options.allowLocalFiles === true) return TOOLS;
  return TOOLS.map((tool) =>
    tool.name === REMOTE_ATTACH_PHOTO_TOOL.name ? REMOTE_ATTACH_PHOTO_TOOL : tool
  );
}

function textResult(value: unknown): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }] };
}

/** Prose for the model, sent as-is rather than JSON-quoted. */
function messageResult(text: string): ToolResult {
  return { content: [{ type: "text", text }] };
}

/** A caption followed by the image it describes. */
function imageResult(
  caption: string,
  image: { data: string; mimeType: string }
): ToolResult {
  return {
    content: [
      { type: "text", text: caption },
      { type: "image", data: image.data, mimeType: image.mimeType },
    ],
  };
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
  args?: Record<string, unknown>,
  options: ToolCallOptions = {}
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

      case "list_exercise_reports":
        return textResult(
          await listExerciseReports({
            status: optionalString(args, "status"),
            category: optionalString(args, "category"),
            exerciseExternalId: optionalString(args, "exerciseExternalId"),
            limit: optionalNumber(args, "limit"),
          })
        );

      case "get_report_photo": {
        const photo = await getReportPhoto(requireString(args, "id"));
        return photo.image
          ? imageResult(photo.caption, photo.image)
          : messageResult(photo.caption);
      }

      case "resolve_exercise_report":
        return textResult(await resolveExerciseReport(args));

      case "list_pending_writes":
        return textResult(
          await listPendingWrites({
            status: optionalString(args, "status"),
          })
        );

      case "delete_inbox_operation":
        return textResult(await deleteInboxOperation(args));

      case "attach_exercise_photo":
        return textResult(
          await attachExercisePhoto(args, {
            allowLocalFiles: options.allowLocalFiles === true,
          })
        );

      case "list_body_measurements":
        return textResult(
          await listBodyMeasurements({
            site: optionalString(args, "site"),
            startDate: optionalString(args, "startDate"),
            endDate: optionalString(args, "endDate"),
            limit: optionalNumber(args, "limit"),
          })
        );

      case "list_medications":
        return textResult(
          await listMedications({
            includeArchived: args?.["includeArchived"] === true,
          })
        );

      case "list_medication_logs":
        return textResult(
          await listMedicationLogs({
            medicationId: optionalString(args, "medicationId"),
            startDate: optionalString(args, "startDate"),
            endDate: optionalString(args, "endDate"),
            limit: optionalNumber(args, "limit"),
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
