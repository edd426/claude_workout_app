# HANDOFF — MCP write path (#88)

Written 2026-07-27 ~21:00, immediately before a Claude Code restart. The restart is
required and it destroys the session that did this work, so everything needed to
finish is here.

## Why a restart was needed

The `workout` MCP server (configured in `~/.claude.json`) loads its code at session
start. It was running the pre-#88 **read-only** build, so the write tools did not
exist in the session's toolset even after `dist/` was rebuilt. Restarting Claude Code
relaunches the server from the new `dist/` and the write tools appear.

## State at handoff — all verified, not assumed

| Piece | State | Evidence |
|---|---|---|
| Functions inbox endpoints | **deployed live** | `az functionapp function list` shows `inboxEnqueue`, `inboxList`, `inboxAck` |
| Cosmos `inbox` container | **created** | `az cosmosdb sql container create`, pk `/id` |
| Functions test suite | **130 passed** | `npm test` in `infra/functions` |
| MCP write tools + catalog | **48 passed**, builds | `npm test`, `tsc --noEmit`, `npm run build` in `infra/mcp` |
| Swift inbox apply-path | **all Swift Testing suites passed** | `xcodebuild test`, 0 issues recorded |
| App on phone | **installed** | `devicectl install` → `com.eddelord.ClaudeLifter`, 2026-07-27 20:52 |
| Functions read path post-deploy | **no regression** | MCP `health` → `authValid: true`; `list_templates` returns the same 3 templates |

Branch `feat/mcp-write-inbox`, committed as `d98ecf8` and pushed. Design:
`infra/MCP_WRITE_PATH.md`.

## The one remaining task — DONE 2026-07-27

All four templates were created via `create_program`, drained by the phone, and
verified with `list_templates`: each has its full exercise list, so the #79
regression did **not** recur. The three unused pre-existing templates (Full Body
Basics, Push Day, Pull Day) were deleted; the April 24 Pull Day *session* survives
in history with a dangling `templateId`. Those deletions exposed **#97** — see
"Known-open" below.

The original brief follows, for reference.

Create four workout templates via MCP. They are the program in
`~/Documents/Analysis/fitness_and_wellness/gym_restart_program.md`, whose first
session is **Wednesday 2026-07-29, 06:00** — so this needs to be done before then.

Every `externalId` below was resolved against `ClaudeLifter/Resources/exercises.json`
and verified to exist. Do not invent or substitute ids; `search_exercises` first if
anything needs changing.

### Upper A
| order | externalId | sets | reps |
|---|---|---|---|
| 0 | `Barbell_Bench_Press_-_Medium_Grip` | 3 | 8 |
| 1 | `Seated_Cable_Rows` | 3 | 10 |
| 2 | `Dumbbell_Shoulder_Press` | 3 | 10 |
| 3 | `Wide-Grip_Lat_Pulldown` | 3 | 10 |
| 4 | `Barbell_Curl` | 2 | 12 |
| 5 | `Triceps_Pushdown_-_Rope_Attachment` | 2 | 12 |

### Lower A
| order | externalId | sets | reps |
|---|---|---|---|
| 0 | `Barbell_Squat` | 3 | 8 |
| 1 | `Romanian_Deadlift` | 3 | 10 |
| 2 | `Leg_Press` | 2 | 12 |
| 3 | `Seated_Calf_Raise` | 2 | 15 |

### Upper B
| order | externalId | sets | reps |
|---|---|---|---|
| 0 | `Incline_Dumbbell_Press` | 3 | 10 |
| 1 | `Wide-Grip_Lat_Pulldown` | 3 | 10 |
| 2 | `Seated_One-arm_Cable_Pulley_Rows` | 3 | 10 |
| 3 | `Side_Lateral_Raise` | 3 | 12 |

### Lower B
| order | externalId | sets | reps |
|---|---|---|---|
| 0 | `Trap_Bar_Deadlift` | 3 | 5 |
| 1 | `Split_Squat_with_Dumbbells` | 2 | 10 |
| 2 | `Seated_Leg_Curl` | 3 | 12 |
| 3 | `Barbell_Ab_Rollout_-_On_Knees` | 2 | 10 |

Leave `defaultWeight` unset — Evan is 7 months detrained and week 1 is ~50% of old
working weights, which he sets at the bar. Omit `defaultRestSeconds`; the phone
injects 90.

## How to do it and how to know it worked

1. `create_program` with all four templates (it validates every externalId before
   enqueueing any, so a typo enqueues nothing).
2. `list_pending_writes` → expect four `pending` operations.
3. **Evan opens the app** — the inbox drains on sync, before the pending-changes
   guard. Templates appear on Home.
4. `list_pending_writes` → the four should now be `applied`. Anything `failed`
   carries the reason in its `error`.
5. `list_templates` → the four new templates, each with its full exercise list.

**A template arriving with zero exercises is the #79 regression and means the fix
failed.** Do not paper over it.

## Known-open, deliberately not blocking

- **#97** — the `requiresApproval` gate has no client implementation.
  `InboxApplier` gates only on `status == "pending"` and never reads
  `requiresApproval`, so approval-required ops apply **unprompted** and then ack
  `pending → applied`, which the server rejects. The op ends `failed` while having
  fully succeeded — so `failed` is not evidence an op did not happen.
- **#95** — apply/ack is not transactional. A dropped ack after a successful local
  apply re-serves the operation and creates a *duplicate* template. If duplicates
  appear, that is why. Delete the extra and fix #95.
- **#88 comment** — `create_custom_exercise` mints a `custom:` externalId that write
  validation cannot resolve, so custom exercises cannot yet be used in templates.
  Irrelevant here: all 17 exercises above are bundled.
- **#96** — four Exercise Library UI tests are permanently red (they query
  `textFields` for a `.searchable` field). Pre-existing, unrelated.

## Review findings logged this session

#89 (mixed weight units corrupt PRs/1RM/volume — the one that matters), #90, #91,
#92, #93, #94, #96.

## Suggested next step after the templates land

Commit `feat/mcp-write-inbox` and open a PR against #88. Nothing is committed yet.
