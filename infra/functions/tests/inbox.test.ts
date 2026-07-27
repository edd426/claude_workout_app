/**
 * Tests for the durable MCP write inbox — issue #88.
 *
 * POST /api/inbox     — validate and enqueue one server-owned operation
 * GET  /api/inbox     — list every operation for one status, oldest first
 * POST /api/inbox/ack — advance operation statuses idempotently
 */

import { app, HttpRequest, InvocationContext } from "@azure/functions";
import { authenticate } from "../src/shared/auth";
import { mockDatabase } from "./__mocks__/cosmos";

// Keep the RED phase runnable before the implementation module exists. Once
// inbox.ts is added, requiring it registers the three handlers under test.
try {
  require("../src/functions/inbox");
} catch (error) {
  const missingInboxModule =
    (error as NodeJS.ErrnoException).code === "MODULE_NOT_FOUND" &&
    String((error as Error).message).includes("../src/functions/inbox");
  if (!missingInboxModule) throw error;
}

const mockApp = app as unknown as { http: jest.Mock };
const mockAuthenticate = authenticate as jest.Mock;

type Doc = Record<string, unknown>;
type Handler = (
  req: unknown,
  ctx: InvocationContext
) => Promise<{ status?: number; jsonBody?: unknown }>;

function findHandler(name: string): Handler {
  const call = mockApp.http.mock.calls.find(([n]: [string]) => n === name);
  if (!call) throw new Error(`${name} handler was not registered with app.http()`);
  return call[1].handler;
}

function findRegistration(name: string): Record<string, unknown> {
  const call = mockApp.http.mock.calls.find(([n]: [string]) => n === name);
  if (!call) throw new Error(`${name} was not registered with app.http()`);
  return call[1];
}

function makeRequest(
  body?: unknown,
  options?: { query?: Record<string, string>; authenticated?: boolean }
) {
  const headers =
    options?.authenticated === false ? {} : { "x-api-key": "test-key" };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return new (HttpRequest as any)(body, headers, { query: options?.query });
}

function isOk(status?: number): boolean {
  return status === undefined || status === 200;
}

function chunk<T>(items: T[], size: number): T[][] {
  const pages: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    pages.push(items.slice(index, index + size));
  }
  return pages;
}

class FakeInboxContainer {
  docs = new Map<string, Doc>();
  pageSize = 2;

  readonly create = jest.fn(async (doc: Doc) => {
    this.docs.set(doc["id"] as string, { ...doc });
    return { resource: doc };
  });

  readonly query = jest.fn(
    (
      querySpec: {
        query: string;
        parameters?: { name: string; value: unknown }[];
      },
      _options?: { maxItemCount?: number }
    ) => {
      const status = querySpec.parameters?.find(
        (parameter) => parameter.name === "@status"
      )?.value;
      const resources = [...this.docs.values()]
        .filter((doc) => status === undefined || doc["status"] === status)
        .sort((left, right) =>
          String(left["createdAt"]).localeCompare(String(right["createdAt"]))
        );
      const pages = chunk(resources, this.pageSize);
      let page = 0;
      return {
        hasMoreResults: () => page < pages.length,
        fetchNext: async () => ({ resources: pages[page++] ?? [] }),
      };
    }
  );

  readonly read = jest.fn(async (id: string) => ({
    resource: this.docs.get(id),
  }));

  readonly replace = jest.fn(async (id: string, doc: Doc) => {
    this.docs.set(id, { ...doc });
    return { resource: doc };
  });

  readonly items = { create: this.create, query: this.query };

  readonly item = jest.fn((id: string, _partitionKey: string) => ({
    read: () => this.read(id),
    replace: (doc: Doc) => this.replace(id, doc),
  }));

  seed(...docs: Doc[]) {
    for (const doc of docs) this.docs.set(doc["id"] as string, { ...doc });
  }
}

let inbox: FakeInboxContainer;

beforeEach(() => {
  inbox = new FakeInboxContainer();
  mockDatabase.container.mockReset();
  mockDatabase.container.mockImplementation((name: string) => {
    if (name !== "inbox") throw new Error(`Unexpected container: ${name}`);
    return inbox;
  });
  mockAuthenticate.mockReturnValue(null);
});

async function enqueue(body: unknown) {
  return findHandler("inboxEnqueue")(makeRequest(body), new InvocationContext());
}

async function list(status?: string) {
  return findHandler("inboxList")(
    makeRequest(undefined, { query: status === undefined ? undefined : { status } }),
    new InvocationContext()
  );
}

async function ack(body: unknown) {
  return findHandler("inboxAck")(makeRequest(body), new InvocationContext());
}

const templateExercise = {
  externalId: "Barbell_Bench_Press_-_Medium_Grip",
  order: 0,
  defaultSets: 3,
  defaultReps: 8,
  defaultWeight: 80,
  defaultRestSeconds: 120,
  notes: "Pause on chest",
};

function pendingOperation(overrides: Doc = {}): Doc {
  return {
    id: "operation-1",
    createdAt: "2026-07-27T10:00:00.000Z",
    op: "createTemplate",
    payload: { name: "Push Day", exercises: [templateExercise] },
    requiresApproval: false,
    status: "pending",
    ...overrides,
  };
}

describe("registration", () => {
  test("POST enqueue registers on inbox", () => {
    const registration = findRegistration("inboxEnqueue");
    expect(registration.methods).toEqual(["POST"]);
    expect(registration.route).toBe("inbox");
  });

  test("GET list registers on inbox", () => {
    const registration = findRegistration("inboxList");
    expect(registration.methods).toEqual(["GET"]);
    expect(registration.route).toBe("inbox");
  });

  test("POST ack registers on inbox/ack", () => {
    const registration = findRegistration("inboxAck");
    expect(registration.methods).toEqual(["POST"]);
    expect(registration.route).toBe("inbox/ack");
  });
});

describe("authentication", () => {
  test.each([
    ["enqueue", "inboxEnqueue", { op: "deleteTemplate", payload: { id: "t1", name: "Push" } }],
    ["list", "inboxList", undefined],
    ["ack", "inboxAck", { results: [] }],
  ])("%s rejects missing or invalid auth before touching Cosmos", async (_label, name, body) => {
    mockAuthenticate.mockReturnValue({
      status: 401,
      jsonBody: { error: "Unauthorized" },
    });

    const response = await findHandler(name)(makeRequest(body), new InvocationContext());

    expect(response.status).toBe(401);
    expect(mockDatabase.container).not.toHaveBeenCalled();
  });
});

describe("POST /api/inbox — enqueue", () => {
  test.each([
    [
      "createTemplate",
      {
        name: "Push Day",
        notes: "Heavy",
        exercises: [templateExercise],
      },
      false,
    ],
    [
      "updateTemplate",
      {
        id: "template-1",
        name: "Push Day v2",
        exercises: [{ ...templateExercise, order: 1 }],
      },
      true,
    ],
    ["deleteTemplate", { id: "template-1", name: "Push Day" }, true],
    [
      "createCustomExercise",
      {
        name: "Cable Katana Extension",
        equipment: "cable",
        primaryMuscles: ["triceps"],
        secondaryMuscles: ["shoulders"],
        instructions: ["Set the pulley low", "Extend overhead"],
        notes: "Keep elbow still",
      },
      false,
    ],
  ])("enqueues a valid %s operation", async (op, payload, requiresApproval) => {
    const response = await enqueue({ op, payload });

    expect(isOk(response.status)).toBe(true);
    const operation = response.jsonBody as Doc;
    expect(operation).toEqual({
      id: expect.stringMatching(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      ),
      createdAt: expect.any(String),
      op,
      payload,
      requiresApproval,
      status: "pending",
    });
    expect(Number.isNaN(Date.parse(operation["createdAt"] as string))).toBe(false);
    expect(inbox.create).toHaveBeenCalledTimes(1);
    expect(inbox.create).toHaveBeenCalledWith(operation);
  });

  test("ignores a client-supplied operation id and assigns a server UUID", async () => {
    const response = await enqueue({
      id: "client-controlled-id",
      op: "createCustomExercise",
      payload: { name: "My Exercise" },
    });

    const operation = response.jsonBody as Doc;
    expect(operation["id"]).not.toBe("client-controlled-id");
    expect(operation["id"]).toEqual(expect.stringMatching(/^[0-9a-f-]{36}$/i));
    expect(inbox.docs.has("client-controlled-id")).toBe(false);
  });

  test("computes requiresApproval server-side so deleteTemplate cannot spoof it", async () => {
    const response = await enqueue({
      op: "deleteTemplate",
      payload: { id: "template-1", name: "Push Day" },
      requiresApproval: false,
    });

    const operation = response.jsonBody as Doc;
    expect(operation["requiresApproval"]).toBe(true);
    expect(inbox.docs.get(operation["id"] as string)?.["requiresApproval"]).toBe(true);
  });

  test("rejects an unknown op before writing", async () => {
    const response = await enqueue({ op: "renameEverything", payload: {} });

    expect(response.status).toBe(400);
    expect(inbox.create).not.toHaveBeenCalled();
  });

  test.each([undefined, "", "   "])(
    "rejects missing or empty externalId (%p) before writing",
    async (externalId) => {
      const exercise = { ...templateExercise, externalId };
      const response = await enqueue({
        op: "createTemplate",
        payload: { name: "Push Day", exercises: [exercise] },
      });

      expect(response.status).toBe(400);
      expect(inbox.create).not.toHaveBeenCalled();
    }
  );

  test.each([
    ["defaultSets", 0],
    ["defaultSets", -1],
    ["defaultSets", 1.5],
    ["defaultReps", 0],
    ["defaultReps", -1],
    ["defaultReps", 2.5],
  ])("rejects invalid %s=%p before writing", async (field, value) => {
    const response = await enqueue({
      op: "createTemplate",
      payload: {
        name: "Push Day",
        exercises: [{ ...templateExercise, [field]: value }],
      },
    });

    expect(response.status).toBe(400);
    expect(inbox.create).not.toHaveBeenCalled();
  });

  test("rejects duplicate exercise order values within one template before writing", async () => {
    const response = await enqueue({
      op: "updateTemplate",
      payload: {
        id: "template-1",
        exercises: [
          templateExercise,
          { ...templateExercise, externalId: "Incline_Dumbbell_Press", order: 0 },
        ],
      },
    });

    expect(response.status).toBe(400);
    expect(inbox.create).not.toHaveBeenCalled();
  });

  test("rejects invalid JSON before writing", async () => {
    const request = makeRequest();
    request.json = async () => {
      throw new Error("bad json");
    };

    const response = await findHandler("inboxEnqueue")(
      request,
      new InvocationContext()
    );

    expect(response.status).toBe(400);
    expect(inbox.create).not.toHaveBeenCalled();
  });
});

describe("GET /api/inbox — list", () => {
  beforeEach(() => {
    inbox.seed(
      pendingOperation({
        id: "pending-newest",
        createdAt: "2026-07-27T12:00:00.000Z",
      }),
      pendingOperation({
        id: "applied",
        createdAt: "2026-07-27T08:00:00.000Z",
        status: "applied",
        appliedAt: "2026-07-27T08:01:00.000Z",
      }),
      pendingOperation({
        id: "pending-oldest",
        createdAt: "2026-07-27T09:00:00.000Z",
      }),
      pendingOperation({
        id: "pending-middle",
        createdAt: "2026-07-27T10:00:00.000Z",
      }),
      pendingOperation({
        id: "failed",
        createdAt: "2026-07-27T11:00:00.000Z",
        status: "failed",
        error: "Unknown exercise",
      })
    );
  });

  test("defaults status to pending, returns oldest-first, and exhausts query pages", async () => {
    inbox.pageSize = 1;

    const response = await list();

    expect(isOk(response.status)).toBe(true);
    const body = response.jsonBody as { operations: Doc[] };
    expect(body.operations.map((operation) => operation["id"])).toEqual([
      "pending-oldest",
      "pending-middle",
      "pending-newest",
    ]);
    const [querySpec, options] = inbox.query.mock.calls[0];
    expect(querySpec.query).toMatch(/WHERE\s+c\.status\s*=\s*@status/i);
    expect(querySpec.query).toMatch(/ORDER\s+BY\s+c\.createdAt\s+ASC/i);
    expect(options?.maxItemCount).toBeGreaterThan(0);
  });

  test("filters by an explicit status", async () => {
    const response = await list("failed");

    const body = response.jsonBody as { operations: Doc[] };
    expect(body.operations.map((operation) => operation["id"])).toEqual(["failed"]);
  });

  test("rejects an unknown status without querying Cosmos", async () => {
    const response = await list("banana");

    expect(response.status).toBe(400);
    expect(inbox.query).not.toHaveBeenCalled();
  });
});

describe("POST /api/inbox/ack", () => {
  test("transitions a pending create operation to applied and stamps appliedAt", async () => {
    inbox.seed(pendingOperation());

    const response = await ack({
      results: [{ id: "operation-1", status: "applied" }],
    });

    expect(isOk(response.status)).toBe(true);
    expect(response.jsonBody).toEqual({
      counts: { updated: 1, unchanged: 0, notFound: 0, invalid: 0 },
    });
    const stored = inbox.docs.get("operation-1");
    expect(stored?.["status"]).toBe("applied");
    expect(Number.isNaN(Date.parse(stored?.["appliedAt"] as string))).toBe(false);
    expect(inbox.replace).toHaveBeenCalledTimes(1);
  });

  test("transitions an approval operation pending to awaitingApproval to applied", async () => {
    inbox.seed(
      pendingOperation({
        op: "updateTemplate",
        payload: { id: "template-1", name: "Updated" },
        requiresApproval: true,
      })
    );

    const awaiting = await ack({
      results: [{ id: "operation-1", status: "awaitingApproval" }],
    });
    expect(isOk(awaiting.status)).toBe(true);
    expect(inbox.docs.get("operation-1")?.["status"]).toBe("awaitingApproval");
    expect(inbox.docs.get("operation-1")?.["appliedAt"]).toBeUndefined();

    const applied = await ack({
      results: [{ id: "operation-1", status: "applied" }],
    });
    expect(isOk(applied.status)).toBe(true);
    expect(inbox.docs.get("operation-1")?.["status"]).toBe("applied");
    expect(Number.isNaN(Date.parse(
      inbox.docs.get("operation-1")?.["appliedAt"] as string
    ))).toBe(false);
    expect(inbox.replace).toHaveBeenCalledTimes(2);
  });

  test.each(["applied", "rejected", "failed"])(
    "acking a terminal %s operation is a no-op success",
    async (status) => {
      inbox.seed(
        pendingOperation({
          status,
          appliedAt:
            status === "applied" ? "2026-07-27T11:00:00.000Z" : undefined,
          error: status === "failed" ? "Already failed" : undefined,
        })
      );

      const before = { ...inbox.docs.get("operation-1") };
      const response = await ack({
        results: [{ id: "operation-1", status: "applied" }],
      });

      expect(isOk(response.status)).toBe(true);
      expect(response.jsonBody).toEqual({
        counts: { updated: 0, unchanged: 1, notFound: 0, invalid: 0 },
      });
      expect(inbox.docs.get("operation-1")).toEqual(before);
      expect(inbox.replace).not.toHaveBeenCalled();
    }
  );

  test("an unknown id does not 500 or write", async () => {
    const response = await ack({
      results: [{ id: "missing-operation", status: "applied" }],
    });

    expect(isOk(response.status)).toBe(true);
    expect(response.jsonBody).toEqual({
      counts: { updated: 0, unchanged: 0, notFound: 1, invalid: 0 },
    });
    expect(inbox.replace).not.toHaveBeenCalled();
  });

  test("a failed ack stores the supplied error", async () => {
    inbox.seed(pendingOperation());

    const response = await ack({
      results: [{ id: "operation-1", status: "failed", error: "No such exercise" }],
    });

    expect(isOk(response.status)).toBe(true);
    expect(inbox.docs.get("operation-1")).toEqual(
      expect.objectContaining({
        status: "failed",
        error: "No such exercise",
      })
    );
  });

  test("validates the complete ack body before rewriting any operation", async () => {
    inbox.seed(pendingOperation());

    const response = await ack({
      results: [
        { id: "operation-1", status: "applied" },
        { id: "", status: "applied" },
      ],
    });

    expect(response.status).toBe(400);
    expect(inbox.replace).not.toHaveBeenCalled();
    expect(inbox.docs.get("operation-1")?.["status"]).toBe("pending");
  });
});

describe("POST /api/inbox/ack — an illegal transition must not poison the batch", () => {
  // An ack batch is sent AFTER the phone has already applied the operations
  // locally. If one bad entry 400s the whole request, the good entries stay
  // `pending`, get re-served on the next sync, and the phone creates duplicate
  // templates. An illegal transition must therefore be recorded as a terminal
  // failure, never allowed to discard its batch-mates or to be re-served.
  test("valid acks in the same batch still apply", async () => {
    inbox.seed(
      pendingOperation({ id: "good", op: "createTemplate", requiresApproval: false }),
      pendingOperation({ id: "bad", op: "deleteTemplate", requiresApproval: true })
    );

    const response = await ack({
      results: [
        { id: "good", status: "applied" },
        // Illegal: an approval-required op cannot jump straight to applied.
        { id: "bad", status: "applied" },
      ],
    });

    expect(response.status ?? 200).toBe(200);
    expect(inbox.docs.get("good")?.["status"]).toBe("applied");
  });

  test("the illegal entry becomes terminally failed, not re-served", async () => {
    inbox.seed(
      pendingOperation({ id: "bad", op: "deleteTemplate", requiresApproval: true })
    );

    await ack({ results: [{ id: "bad", status: "applied" }] });

    const stored = inbox.docs.get("bad");
    expect(stored?.["status"]).toBe("failed");
    expect(String(stored?.["error"])).toMatch(/transition/i);

    // Re-served only if still pending — a poison pill would loop forever.
    const listed = await list("pending");
    expect((listed.jsonBody as { operations: unknown[] }).operations).toHaveLength(0);
  });
});
