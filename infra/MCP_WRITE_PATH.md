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
  op: "createTemplate" | "updateTemplate" | "deleteTemplate"
    | "createCustomExercise" | "resolveExerciseReport" | "setExercisePhoto";
  payload: object;         // op-specific, validated at enqueue
  requiresApproval: boolean; // server-computed: true for updateTemplate,
                             // deleteTemplate and setExercisePhoto
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
| `/api/inbox/ack` | POST | Body `{ results: [{ id, status, error? }] }`. Retrying the operation's current status is an idempotent no-op. An invalid transition fails a nonterminal operation so it cannot loop; a terminal disagreement stays unchanged. Both return a per-operation `conflict` outcome. |

### Status machine

```
pending ──► applied | failed                      (creates: applied on fetch)
pending ──► awaitingApproval ──► applied | rejected | failed   (update/delete/setExercisePhoto)
```

The phone acks **every** pending operation it fetches in the same cycle — creates
as `applied`/`failed`, approval-required ops as `awaitingApproval` — before it
mutates any approval-required operation. It separately refetches
`awaitingApproval` operations for the Home approval UI, including after an app
restart. Applied and rejected docs are retained as an audit trail.

Ack responses include one result per requested id:

```ts
{
  counts: { updated, unchanged, notFound, invalid },
  results: [{
    id,
    requestedStatus,
    resultingStatus?,
    outcome: "updated" | "unchanged" | "notFound" | "conflict",
    conflict?
  }]
}
```

The iOS client treats malformed, missing, extra, `notFound`, or `conflict`
results as a sync error, but still pushes locally applied batch-mates. A
nonterminal conflict is durably rewritten to `failed` with the reason so it is
not served forever. An already-terminal operation receiving a different status
remains unchanged.

### Payloads

```ts
// `defaultRestSeconds` is optional on the wire and non-optional in iOS
// (#79 root cause 3). The PHONE owns the default: it injects 90 when the
// field is absent. The Function preserves omission and never injects — one
// layer owns the default, and it is the layer whose type demands a value.

// createTemplate — no client-supplied UUID. The phone deterministically uses
// the inbox operation UUID, so replaying a create after a lost ack is a no-op.
{ name: string, notes?: string,
  exercises: [{ externalId: string, order: number, defaultSets: number,
                defaultReps: number, defaultWeight?: number,
                defaultRestSeconds?: number /* default 90 */, notes?: string,
                alternatives?: [{ externalId: string, note?: string }] }] }

// updateTemplate — `exercises`, when present, REPLACES the whole ordered list.
{ id: string /* template UUID from list_templates */, name?: string,
  notes?: string, exercises?: [ ...as above ] }

// alternatives (issue #169) — substitutes for a slot when the machine is
// taken, in preference order. TRI-STATE on the phone:
//   key absent → keep the slot's current list (matched to the rebuilt slot by
//                externalId, slot by slot for duplicates — the same rule as the
//                approval diff)
//   []         → clear it
//   [ ... ]    → replace it
// `null` is refused at both the MCP tool and the Function (ambiguous between
// keep and clear). Each alternative externalId is validated exactly like the
// slot's own: catalog/custom resolution at the MCP tool, non-empty string at
// the Function, strict resolution on the phone, where an unknown one fails the
// whole operation. The MCP tool sends each entry as exactly {externalId, note?}.

// setExercisePhoto (issue #170) — REQUIRES APPROVAL. Points an exercise's
// photo at a JPEG that attach_exercise_photo has ALREADY uploaded:
{ externalId: string, blobPath: string /* exactly "exercises/ext/{externalId}.jpg" */ }
// The Function stores exactly these two keys and refuses any blobPath other
// than the externalId's own path, and any externalId outside the photo-path
// grammar (catalog [A-Za-z0-9][A-Za-z0-9_-]{0,127}, or
// custom:{slug≤64}:{lowercase uuid}). On approval the phone sets
// Exercise.photoURL = blobPath (bundled exercises carry it through the #140
// overlay into sync and backup) and downloads it with a read SAS. An unknown
// externalId fails the op; a declined op changes nothing.

// deleteTemplate — name carried so the approval banner needs no lookup.
{ id: string, name: string }

// createCustomExercise input — no externalId accepted from the producer.
{ name: string, equipment?: string, primaryMuscles?: string[],
  secondaryMuscles?: string[], instructions?: string[], notes?: string }

// resolveExerciseReport (issue #135) — closes out a user-filed complaint.
// Approval-free by design: the point of the status lifecycle is that the
// backlog can be cleared without a second confirmation, and the write is
// trivially reversible. `status` omitted means "resolved"; "open" is REJECTED
// at the Function — an inbox operation exists to close a report, never to
// reopen one behind the user's back.
{ id: string /* report UUID from list_exercise_reports */,
  status?: "resolved" | "acknowledged", resolution?: string }

// Stored createCustomExercise payload — the Function adds this canonical id:
// "custom:<ascii-name-slug>:<inbox-operation-uuid>"
// slug grammar: lowercase alphanumeric hyphen-separated segments, 1...64 chars
// The phone uses the inbox UUID as the Exercise UUID and consumes this
// server-issued externalId verbatim.
```

## Validation — three layers, deliberately redundant

1. **MCP tool boundary.** Bundled `externalId`s resolve against a slim catalog
   index generated at build time from `ClaudeLifter/Resources/exercises.json`
   (~1 MB → id/name/muscles/equipment/category only). `custom:` ids resolve
   against the cloud snapshot or a durable pending/applied
   `createCustomExercise` inbox operation, so a custom exercise can be used in a
   template even before the phone's next snapshot push. An unknown id is rejected
   *before* the template HTTP POST, with `search_exercises` suggestions in the
   error.
2. **Function enqueue.** Structural: `externalId` non-empty strings, positive
   integer sets/reps, unique `order`. Custom exercise ids are minted as
   `custom:<slug>:<operation-uuid>` with a 64-character slug bound. Rejects with
   400 before any write.
3. **Phone apply.** `fetchByExternalId` **strictly** — no fuzzy fallback, no
   placeholder creation. If any exercise in an operation fails to resolve, the
   **entire operation fails** and is acked `failed` with the unresolved ids. A
   partial template is precisely the bug that started this; half-applying is worse
   than failing loudly. A custom exercise payload must use the same bounded
   grammar and its UUID suffix must equal the inbox operation UUID.

## Sync ordering — the trap

`SyncManager.syncIfNeeded()` returns early when there are no pending local changes
(`SyncManager.swift:132`). Fetching the inbox after that guard means **MCP writes
never arrive on an idle phone** — the common case, since the phone is idle exactly
when Claude is writing. Required order:

1. Fetch inbox + apply (before any pending-changes guard)
2. Ack results
3. `hasPendingChanges()` — now true, because applying marked new templates `.pending`
4. `pushSnapshot()`

When any inbox operation applies locally, `SettingsManager.isSnapshotDirty` is
set in UserDefaults before the ack. It is cleared only after a snapshot push
succeeds. This is required for custom exercises, which have no per-record
`syncStatus`: a failed push followed by an app restart still retries even if the
inbox is then empty.

## Approval — server-durable, no SwiftData queue

Update and delete operations never mutate local data while `pending`. The phone
first acks them `awaitingApproval`, then refetches that durable server state and
shows one Home approval card per operation. The card follows the app's existing
confirmation pattern and opens a confirmation dialog with Approve, Decline, and
Cancel.

- Approve applies locally, acks `applied`, and pushes the dirty snapshot.
- Decline acks `rejected` and performs no repository mutation.
- A restart loses no queue state: `awaitingApproval` is refetched from the
  server and shown again.

There is deliberately **no new SwiftData `@Model`** for approvals, so this change
does not require an AppSchema version bump or migration.

## Create replay safety

`createTemplate` and `createCustomExercise` derive their local entity UUID from
the Function-assigned inbox operation UUID. Before inserting, the applier fetches
that UUID through the repository; if it already exists, replay is a successful
no-op. A lost ack can therefore re-serve a create without inserting a duplicate.

Custom external ids are minted once by the Function as
`custom:<slug>:<operation-uuid>`. The reserved prefix keeps them separate from
bundled ids, and the operation suffix disambiguates names that normalize to the
same slug. Swift does not duplicate the TypeScript slug algorithm.

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
| `list_exercise_reports` | Reads the complaint backlog mirrored by snapshot sync (`GET /api/reports`). Not an inbox operation. |
| `get_report_photo` | Reads a report's photo (#141): validates `photoURL` as `reports/{reportId}.jpg`, then downloads it with a read SAS from `GET /api/images/sas`. Read-only, not an inbox operation. |
| `resolve_exercise_report` | Enqueues `resolveExerciseReport`. Auto-applies. |
| `attach_exercise_photo` | #170. Takes exactly one of `imagePath` (a local `.jpg`/`.jpeg`, read with symlinks resolved; local stdio server only, refused by the remote server) or `imageBase64`. Validates the externalId (photo-path grammar, then catalog/custom resolution) and the image (JPEG, ≤ 3.75 MB) before any request; gets a **write** SAS for `exercises/ext/{externalId}.jpg` from `GET /api/images/sas`; uploads straight to Blob Storage (the SAS is the only credential sent there, never the API key); only then enqueues `setExercisePhoto`. Requires approval. |
| `list_pending_writes` | Reads back queued/applied/failed operations — closes the loop so a write can be *verified*, not assumed. |

### Photo blobs are written before the operation exists

`setExercisePhoto` is the one operation whose effect is partly outside the
inbox: the JPEG is already in `workout-images` when the operation is queued.
Two consequences:

- **Known limitation, accepted (2026-11-03): declining a re-attach does not
  restore the old photo.** The path is deterministic per exercise, as the
  issue specified, so attaching again overwrites the blob before anyone
  approves anything. A *declined* re-attach therefore still replaces the bytes
  an earlier *approved* op points at. A phone that cached the earlier image
  keeps showing it until it re-downloads. Evan's call: acceptable for now. If
  it ever matters, the fix is a per-upload path
  (`exercises/ext/{externalId}/{opId}.jpg`) with the same grammar for the id
  segment.
- **A phone build without `setExercisePhoto` support** acks the op `failed`
  ("Unknown inbox operation"); it is isolated to that op. The blob stays, so
  re-running the tool after the phone update is enough.

## Out of scope

Workout-session and body-weight writes (deliberately deferred — corrupting logged
training data is the most damaging failure mode and there is no need for it yet).
The same goes for body measurements and the medication log (#164, #165): MCP
reads them (`list_body_measurements`, `list_medications`,
`list_medication_logs`) and never writes them.
