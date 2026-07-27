# MCP Write Path — Inbox Design

Status: design agreed 2026-07-27. Supersedes the disabled write tools from #79.

## The problem the obvious design gets wrong

Writing templates from MCP straight into Cosmos **cannot work**, and not for the
reason #79 recorded. `syncSnapshot.ts` reconciles each container to exactly the
phone's snapshot: it upserts every doc in the push, then **deletes every doc whose
id is not in it** (`syncSnapshot.ts:212-225`). The phone doesn't know about an
MCP-written template, so the template is absent from the next snapshot, so the
server deletes it. Any direct write to the mirror is erased on the next sync.

The mirror is a projection of the phone. Writes have to reach the phone.

## Exercise identity — the other half of #79

`ExerciseImportService.swift:49` constructs `Exercise(...)` without an `id`, so
`Exercise.id` is a **random UUID assigned at import time on that install**. That is
why MCP-invented `exerciseId`s never resolved and why templates arrived empty.

`Exercise.externalId` holds the free-exercise-db string id
(`Barbell_Bench_Press_-_Medium_Grip`), is stable across installs, and is already in
the repo at `ClaudeLifter/Resources/exercises.json`. `ExerciseRepository` already
exposes `fetchByExternalId(_:)`.

**Rule: MCP references exercises by `externalId`, never by UUID. The phone
resolves.** No cloud exercise catalog needs to be seeded.

## Architecture

A durable **inbox** of proposed operations that the phone drains on sync.

```
MCP write tool
    │  validates externalIds against the bundled catalog  ← invented exercises die here
    ▼
POST /api/inbox ──────────► Cosmos `inbox` container   (NOT in SNAPSHOT_COLLECTIONS)
                                    │
                     GET /api/inbox │ (phone, every sync, BEFORE the pending-changes guard)
                                    ▼
                            apply in SwiftData
                        creates → applied immediately
              update/delete → held for user approval on Home
                                    │
                     POST /api/inbox/ack
                                    ▼
                       normal snapshot push makes them real in the mirror
```

The phone stays authoritative. The snapshot contract is untouched.

## Wire contract

New Cosmos container `inbox`, partition key `/id`. Excluded from
`SNAPSHOT_COLLECTIONS` — snapshot reconciliation must never see it.

```ts
interface InboxOperation {
  id: string;              // uuid, assigned by the Function (never the client)
  createdAt: string;       // ISO 8601, server clock
  op: "createTemplate" | "updateTemplate" | "deleteTemplate" | "createCustomExercise";
  payload: object;         // op-specific, validated at enqueue
  requiresApproval: boolean; // server-computed: false for creates, true for update/delete
  status: "pending" | "awaitingApproval" | "applied" | "rejected" | "failed";
  appliedAt?: string;
  error?: string;          // set when status === "failed"
}
```

### Endpoints

| Endpoint | Method | Behaviour |
|---|---|---|
| `/api/inbox` | POST | Body `{ op, payload }`. Validates, assigns `id`/`createdAt`/`requiresApproval`, sets `status: "pending"`, returns the stored doc. |
| `/api/inbox` | GET | `?status=` (default `pending`). Returns `{ operations: [...] }` oldest-first. |
| `/api/inbox/ack` | POST | Body `{ results: [{ id, status, error? }] }`. Terminal-state writes are idempotent no-ops. Returns counts. |

### Status machine

```
pending ──► applied | failed                      (creates: applied on fetch)
pending ──► awaitingApproval ──► applied | rejected | failed   (update/delete)
```

The phone acks **every** operation it fetches in the same cycle — creates as
`applied`/`failed`, approval-required ops as `awaitingApproval` — so nothing is
served twice. Applied and rejected docs are retained as an audit trail.

### Payloads

```ts
// `defaultRestSeconds` is optional on the wire and non-optional in iOS
// (#79 root cause 3). The PHONE owns the default: it injects 90 when the
// field is absent. The Function preserves omission and never injects — one
// layer owns the default, and it is the layer whose type demands a value.

// createTemplate — no client-supplied UUID; the phone assigns it.
{ name: string, notes?: string,
  exercises: [{ externalId: string, order: number, defaultSets: number,
                defaultReps: number, defaultWeight?: number,
                defaultRestSeconds?: number /* default 90 */, notes?: string }] }

// updateTemplate — `exercises`, when present, REPLACES the whole ordered list.
{ id: string /* template UUID from list_templates */, name?: string,
  notes?: string, exercises?: [ ...as above ] }

// deleteTemplate — name carried so the approval banner needs no lookup.
{ id: string, name: string }

// createCustomExercise — phone assigns the UUID, sets isCustom = true and
// externalId = "custom:<slug-of-name>" so later template writes can reference it.
{ name: string, equipment?: string, primaryMuscles?: string[],
  secondaryMuscles?: string[], instructions?: string[], notes?: string }
```

## Validation — three layers, deliberately redundant

1. **MCP tool boundary.** Every `externalId` is resolved against a slim catalog
   index generated at build time from `ClaudeLifter/Resources/exercises.json`
   (~1 MB → id/name/muscles/equipment/category only). An unknown id is rejected
   *before* the HTTP call, with `search_exercises` suggestions in the error. This
   is the fix for #79 root cause 2 — an invented exercise can no longer be
   enqueued at all.
2. **Function enqueue.** Structural: `externalId` non-empty strings, positive
   integer sets/reps, unique `order`. Rejects with 400 before any write.
3. **Phone apply.** `fetchByExternalId` **strictly** — no fuzzy fallback, no
   placeholder creation. If any exercise in an operation fails to resolve, the
   **entire operation fails** and is acked `failed` with the unresolved ids. A
   partial template is precisely the bug that started this; half-applying is worse
   than failing loudly.

## Sync ordering — the trap

`SyncManager.syncIfNeeded()` returns early when there are no pending local changes
(`SyncManager.swift:132`). Fetching the inbox after that guard means **MCP writes
never arrive on an idle phone** — the common case, since the phone is idle exactly
when Claude is writing. Required order:

1. Fetch inbox + apply (before any pending-changes guard)
2. Ack results
3. `hasPendingChanges()` — now true, because applying marked new templates `.pending`
4. `pushSnapshot()`

## Approval — decided against an in-app queue (2026-07-27)

An earlier draft queued update/delete in a local `PendingWriteApproval` model behind
a Home approval banner. **Dropped at Evan's direction:** for a single-user app the
approval already happens in conversation — he asks for the change, then it is made.
An in-app banner re-confirms a decision he just made, one screen later.

Consequences, both good:

- **No new `@Model`, so no SwiftData schema change**, and none of the on-device
  migration risk that has bitten this app before.
- All four operations auto-apply on sync. `awaitingApproval` stays in the Function's
  status machine as an unused-but-valid state rather than being ripped out, so a
  future UI can adopt it without a wire change.

The safety net for a destructive mistake is the existing cloud snapshot restore plus
backup export — not a confirmation tap. A deleted template's absence from the next
snapshot propagates the delete to the mirror; no tombstones needed.

## MCP tool surface

Re-enabled / new:

| Tool | Notes |
|---|---|
| `search_exercises` | Bundled catalog index + cloud `customExercises`. No longer queries the empty container. |
| `create_template` | Enqueues `createTemplate`. Auto-applies on the phone. |
| `update_template` | Enqueues `updateTemplate`. Requires approval. |
| `delete_template` | Enqueues `deleteTemplate`. Requires approval. |
| `create_program` | N × `createTemplate` in one call, all-or-nothing validation. |
| `create_custom_exercise` | Enqueues `createCustomExercise`. Auto-applies. |
| `list_pending_writes` | Reads back queued/applied/failed operations — closes the loop so a write can be *verified*, not assumed. |

## Out of scope

Workout-session and body-weight writes (deliberately deferred — corrupting logged
training data is the most damaging failure mode and there is no need for it yet).
