# HANDOFF — MCP write path

Updated 2026-07-28. **PR #108 is merged** (`362fd3b`) and the branch is deleted.
Nothing is in flight. This file is now a state-of-the-write-path summary; read it
before touching sync, the inbox, or the MCP write tools.

## Where the write path stands

#88 is complete. Claude Code and claude.ai can create templates through MCP:
writes land in a durable Cosmos `inbox` that the phone drains on sync. Writes
cannot go straight to Cosmos — the phone is authoritative and its next snapshot
would erase them. Design: `infra/MCP_WRITE_PATH.md`; trust it and
`syncSnapshot.ts` over SPEC §7/§11, which are stale on sync.

**Proven end to end in production**: four templates created via MCP, drained by
the phone, verified with full exercise lists — the #79 regression (templates
arriving empty) did not recur. Build installed to the phone 2026-07-28.

Closed by #108: **#97** (approval gate had no client implementation) and
**#95** (lost ack duplicated the write).

## What #108 established

- Approval-required operations ack `awaitingApproval` **before** any mutation;
  Home surfaces them; they apply only on explicit approve, `rejected` on decline.
- Approval is derived from the operation **type** on both phone and server, so a
  malformed or legacy envelope claiming `requiresApproval: false` cannot
  auto-apply an update or delete. A flag/type mismatch fails terminally.
- Creates derive entity identity from the operation id → replay upserts.
- Ack semantics: same-status retry is an idempotent no-op; terminal operations
  are never overwritten; an illegal transition from a **nonterminal** state still
  goes terminal (leaving it pending would re-serve it every sync forever) but is
  reported per-operation. A conflict no longer blocks `pushSnapshot`.
- Durable snapshot-dirty marker; server-issued `custom:<slug>:<operation-uuid>`
  external ids under one grammar across MCP, Functions, and the phone.

## Known-open — read before touching the write path

- **#103** — approval decisions are **not durable**. A lost *final* ack still lets
  a user contradict a decision already applied, and `updateTemplate` can replay
  over an intervening edit. Needs a local operation receipt keyed by operation id.
  **Biggest remaining gap; the natural next piece of work.**
- **#104** — UI-created custom exercises are never pushed (`Exercise` is absent
  from `hasPendingChanges`). **Pre-existing**; the dirty marker covers only the
  inbox case.
- #98 partial `create_program` enqueue · #99 import/sync ordering race ·
  #100 Home staleness after apply · #101 stale-write preconditions ·
  #102 producer-side enqueue idempotency · #105 MCP trusting historical `applied`
  records · #106 unconditional Cosmos replace on ack · #107 approval prompt
  trusts the payload name.
- **#96** — four Exercise Library UI tests are permanently red (they query
  `textFields` for a `.searchable` field). Pre-existing, unrelated.

## Verified state as of 2026-07-28

| Piece | State |
|---|---|
| Swift Testing suites | 650 passed (iPhone 13 Pro Max / iOS 26.5) |
| XCUITest | 4 failing — pre-existing #96 |
| Functions (Jest) | 145 passed |
| MCP (vitest) | 52 passed, tsc clean, builds |
| Functions inbox endpoints | deployed live (`inboxEnqueue`, `inboxList`, `inboxAck`) |
| Cosmos `inbox` container | created, pk `/id` |
| App on phone | installed 2026-07-28 from merged code |

## Gotchas worth keeping

- The `workout` MCP server loads its code at **session start**. After rebuilding
  `infra/mcp/dist/`, Claude Code must be restarted before new tools appear.
- The **iPhone 13 Pro Max simulator may not exist** and must be created rather
  than substituted (`xcrun simctl create` against the iOS 26.5 runtime). iPhone 17
  is documented to produce a false `ChatCoachTests` failure.
- The physical device destination in CLAUDE.md uses a **typographic apostrophe**
  in "Evan DeLord’s iPhone"; a straight quote fails to match. Prefer
  `-destination 'platform=iOS,id=<id>'` from `xcodebuild -showdestinations`.
- **`xcodebuild test` exits 65 even when your change is fine**, because of #96.
  Those are XCUITest and print `Test Case '-[...]' failed`, so grepping only
  Swift Testing's `✘` format misses them. Read the `Failing tests:` block and
  diff it against a baseline run. Never pipe `xcodebuild` through `tail` without
  `set -o pipefail` — it masks the exit code.
- Static typechecks are not a test run. Two rounds of this work typechecked
  cleanly and still failed the simulator suite.
- Writing "Closes #97 and #95" links only the **first** issue. Use a separate
  `Closes #N` per issue.
