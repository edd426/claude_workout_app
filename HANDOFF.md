# HANDOFF — MCP write path (#88)

Updated 2026-07-27 ~23:30. The original handoff task is **done**; this file now
describes where the write path actually stands.

## Current state

**PR #108 is open** against `main` from `feat/mcp-write-inbox` (head `87b6ac7`).
It completes #88 and closes #97 and #95. Nothing is blocked; the PR is awaiting
review/merge.

| Piece | State | Evidence |
|---|---|---|
| Functions inbox endpoints | deployed live | `az functionapp function list` shows `inboxEnqueue`, `inboxList`, `inboxAck` |
| Cosmos `inbox` container | created | pk `/id` |
| Swift suite | **650 passed** | `xcodebuild test`, iPhone 13 Pro Max / iOS 26.5 |
| Functions (Jest) | **145 passed** | `npm test` in `infra/functions` |
| MCP (vitest) | **52 passed**, tsc clean, builds | `infra/mcp` |
| Write path end-to-end | **proven in production** | 4 templates created via MCP, drained by the phone, full exercise lists — no #79 regression |

The four gym-restart templates (Upper A / Lower A / Upper B / Lower B) are live on
the phone. The three unused pre-existing templates were deleted; the April 24
Pull Day *session* survives in history with a dangling `templateId`.

Design: `infra/MCP_WRITE_PATH.md` — trust it and `syncSnapshot.ts` over SPEC §7/§11.

## What PR #108 changed

- **#97** — the `requiresApproval` gate had no client implementation, so
  approval-required operations applied unprompted and were then recorded `failed`
  despite succeeding. The applier now acks `awaitingApproval` before mutating,
  Home surfaces approvals, and approval is derived from operation **type** so a
  malformed envelope cannot auto-apply an update or delete.
- **#95** — creates derive entity identity from the operation id, so a re-served
  operation upserts rather than duplicating.
- Ack semantics: same-status retry is a no-op; terminal operations are never
  overwritten; illegal transitions from a nonterminal state still go terminal
  (otherwise they re-serve forever) but are now reported per-operation. A conflict
  no longer blocks `pushSnapshot`.
- Durable snapshot-dirty marker; server-issued `custom:<slug>:<operation-uuid>`
  external ids under one grammar across MCP, Functions, and the phone.

## Known-open — read before touching the write path

- **#103** — approval decisions are **not durable**. A lost final ack still lets a
  user contradict a decision already applied, and `updateTemplate` can replay over
  an intervening edit. Needs a local operation receipt. Biggest remaining gap.
- **#104** — UI-created custom exercises are never pushed (`Exercise` is absent
  from `hasPendingChanges`). **Pre-existing**; the dirty marker covers only the
  inbox case.
- #98 partial `create_program` enqueue · #99 import/sync ordering race ·
  #100 Home staleness · #101 stale-write preconditions · #102 producer-side
  enqueue idempotency · #105 MCP trusting historical `applied` records ·
  #106 unconditional Cosmos replace on ack · #107 approval prompt trusts the
  payload name.
- **#96** — four Exercise Library UI tests are permanently red (they query
  `textFields` for a `.searchable` field). Pre-existing, unrelated.

## Gotchas worth keeping

- The `workout` MCP server loads its code at **session start**. After rebuilding
  `infra/mcp/dist/`, Claude Code must be restarted before new tools appear.
- The **iPhone 13 Pro Max simulator did not exist** on this machine and had to be
  created (`xcrun simctl create` against the iOS 26.5 runtime). Do not substitute
  iPhone 17 — it is documented to produce a false `ChatCoachTests` failure.
- Static typechecks are not a test run. Two separate rounds of this work passed
  typechecking and still failed the simulator suite (once a real product defect,
  once non-UUID test fixtures). Always run `xcodebuild test`.
