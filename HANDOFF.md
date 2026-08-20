# HANDOFF — 1.4.1 is installed and the migration held

Updated 2026-08-20. Branch **`feat/exercise-reports`**, **PR #145**. `main`
untouched. **Version 1.4.1 (6) is on the phone** — Release build, installed
2026-08-20 06:00 local and launched.

**The schema V4 migration succeeded on real data.** Proof is not that the app
opened — a quarantined store opens fine, empty. It is that the phone synced
after launch and the mirror went revision **378 → 380 with counts intact**: 17
workouts, 5 templates, 6 reports, 2320 body-weight entries. A quarantine would
have pushed an empty snapshot and wiped the mirror instead.

Also settled on launch: the Functions app is deployed and verified at wire v4,
the Cosmos `exerciseOverlays` container exists (created through Bicep), and the
**Lower B Split Squat edit applied** — the template now reads 2 × 8.

What is left is the gym: the probes below all need a human at a machine.

## Do this first

1. ~~Install 1.4.1 (6)~~ — **done**, and the V4 migration held (see above).
   Sanity-check the Settings footer reads `1.4.1 (6)` anyway.
2. Run the gym probes in the table below.
3. Resolve the three acknowledged reports once the probes pass.
4. ~~Approve the pending Lower B edit~~ — **approved on the phone** and applied
   at 04:01 UTC, op `43593a49-…`; Lower B now reads Split Squat 2 × 8. The
   approval guardrail fired correctly (screenshot confirms the prompt), but the
   prompt showed no diff — **#147**. Report `990C04B4` stays open until you
   train it.

## The probes, in the gym

| Probe | Expected |
|---|---|
| **#136** Seated Leg Curl → ⋯ → *Add a note…* → `Ankle 4; Seat 4; Pivot 1` | The note appears on the card, and on **every** future workout containing that exercise, whichever template |
| **#137** Add Ab Crunch Machine mid-workout | Its sets arrive with reps prefilled from last session and **weight empty**. Empty weight is the fix working |
| **#144** Any Lower B exercise | A `Target 2 × 8 · 90s rest` line under the name, and last session's PREVIOUS marked orange where it missed the target |
| **#140** Note a bundled exercise, then Settings → sync | The note appears in the `exerciseOverlays` Cosmos container, keyed by `externalId` (e.g. `Seated_Leg_Curl`). The server side is already verified; this probe tests the phone half |
| **#129/#130** Finish a Lower B with Ab Crunch Machine added | The summary offers *Update Lower B?* → Review → Apply. Ab Rollout, if skipped, must **not** be offered for removal |

## What changed, and the three things worth knowing

### #136 — the issue's own fix would have done nothing

Copying `TemplateExercise.notes` into the session is correct and inert: the
**Lower B template has no notes on any exercise**. The `"Ankle 4; Seat 4;
Pivot 1"` note lived on the *2026-08-12 session*, and nothing in the app writes
that field — it arrived via sync and died with the session. A session-scoped
note typed at the machine would have vanished again a week later and produced
the same report.

The note now lives on the library `Exercise`, per Evan: *"if I make a new
workout with the same exercise, I want the same note to appear with it."*

### #128 — this project cannot version a property-only schema change

The first attempt did exactly what the issue asked — provenance fields on
`Workout` and `WorkoutExercise` — and died with:

```
NSInvalidArgumentException: Duplicate version checksums detected
```

The `VersionedSchema` model lists in `AppSchema.swift` name **live Swift
types**, so they are not frozen history. Adding a property to `Workout` changes
what V1, V2 and V3 mean as well as V4; all four then hash identically and
SwiftData refuses to open the store. That is a hard crash on the first launch
after an update, not a recoverable migration failure.

**With live types, a new schema version can only differ by its model LIST.** Any
future property-only change faces this, and the only alternatives are freezing
copies of every affected model, or adding a new model instead.

Provenance therefore lives in two new models — `WorkoutTemplateBaseline` and
`WorkoutExerciseBaseline` — referencing the workout by plain UUID rather than a
`@Relationship`, because a relationship means a stored property on `Workout` and
brings the crash straight back.

**The on-disk migration test caught this. The in-memory containers the rest of
the suite uses passed the entire time.** `TemplateProvenanceMigrationTests`
builds a genuine V3 store and reopens it through `ModelContainerFactory` — copy
that for any future migration.

Consequence for **#110**: nutrition needs **V5**, and if it adds properties
rather than models it hits the same wall.

### #139 — a draft in the mirror, not a broken Finish

Workout `5743E0DD` carries `completedAt: 2026-08-19T05:02:47.955Z`. The record's
`_ts` advanced between two reads while the phone caught up on sync, so the state
the issue was filed from was a **mid-workout draft push**.

`SyncManager.pushSnapshot` pushes every workout with no `completedAt` filter and
nothing labels a draft as one, so a draft is indistinguishable from a stranded
session. That cost an issue, a triage and a handoff entry. Filed as **#143**.

Until it is fixed: **a workout with no `completedAt` in the mirror is more
likely a draft than a bug.** Re-read the record before filing; a moving `_ts`
means the phone is still catching up.

The timestamp oddity resolved too — Seated Leg Curl (order 2) was performed
before Split Squat (order 1), and there is no batch-completion path anywhere:
`completedAt` is written one set at a time, in exactly two places. Pinned with
tests.

## Blocked — nothing, as of 2026-08-20

**Nothing.** Both actions that were blocked are done.

The Functions app is **deployed and verified at wire version 4**, and the
Cosmos container was created **through Bicep** rather than an ad-hoc `az`
command, so the repo still describes reality.

Verified against production, read-only — a real push would have reconciled the
live mirror, so the version checks used bodies that fail validation, which runs
before any write:

| Probe | Result |
|---|---|
| `GET /api/health` | 200 |
| `GET /api/sync/snapshot` | revision **378**, and the mirror now returns an `exerciseOverlays` collection (empty — no phone has pushed one yet) |
| `POST` schemaVersion 9 | `Expected one of 2, 3, 4` — v4 is live |
| `POST` schemaVersion 4, no overlays key | rejected *by name* — v4 dispatch reaches the overlay collection |
| `POST` schemaVersion 3 | still a known version — back-compat intact for the phone on 1.2.0 |

Mirror contents unchanged throughout: 17 workouts, 5 templates, 2319
body-weight entries, 6 reports.

The client's degrade-to-v3 path stays in regardless. It is now belt and
braces rather than load-bearing, and it means the next wire bump can ship in
either order.

### On deploying with Bicep — read this before you try

`what-if` earned its keep. Deploying `cosmos.bicep` as written would have made
three changes nobody asked for: `enableAutomaticFailover` **off**,
`minimalTlsVersion` **dropped**, and a database-throughput rewrite. The live
account had all three set correctly and the template declared none of them, so
the template was quietly proposing to weaken production. Two are now declared;
the third was a false alarm (autoscale max 1000 already matches).

**Do not deploy `main.bicep` whole without re-publishing the code after.**
`functions.bicep`'s `appSettings` array is wholesale — ARM replaces the entire
setting collection — and the live app carries `WEBSITE_RUN_FROM_PACKAGE`, a
rotating SAS URL that cannot be expressed in Bicep. Deploying strips it and the
API 404s until `func publish` runs. The runbook is in a comment at the top of
that resource. For Cosmos-only work, deploy the module alone: no secrets, no
Function App, `what-if` first.

## Test state


| Suite | Result |
|---|---|
| Swift unit (`-only-testing:ClaudeLifterTests`) | **781 tests, 98 suites, exit 0** |
| Azure Functions (jest) | **180 pass** |
| MCP server (vitest) | **64 pass** (60 + 4 for the staleness guard) |
| XCUITest | **not run** — flaky here; not a regression without a clean-worktree comparison |

The unit suite is the hard gate: deterministic and green.

## Deferred deliberately

- **#130's remembered policies** (Ask/Always/Never per category) and the
  Settings → Workout & Templates screen. They configure a behaviour nobody has
  lived with yet; use the review flow first, then decide what to remember.
- **"Save as new template"** for ad-hoc workouts — they have no baseline, so
  they never reach the review card at all.
- **Target reps and rest in #129's detection.** No UI changes either
  mid-workout — `WorkoutExercise.restSeconds` is written once at construction
  and never mutated — so any difference would be noise rather than intent. When
  such a control exists, `TemplateChangeDetector` is where it plugs in.

## New issues filed this session

- **#140** bundled-exercise user data excluded from sync and backup — **both halves done**, pending the Functions publish
- **#141** photo upload on exercise reports
- **#142** search the library from the report sheet
- **#143** the mirror cannot distinguish a draft from a finished workout
- **#144** target reps on the workout screen + drift marker
- **#146** `acknowledged` reports read as done but count as open, and *Show
  resolved* can never do anything — no report ever reaches `resolved`. Live
  data confirms: 3 acknowledged, 3 open, **0 resolved**
- **#147** *Review Change* shows no change — the inbox approval prompt is a
  `confirmationDialog` whose whole message is an exercise **count**, so a
  one-number edit is indistinguishable from a full rewrite

---

# Still true from the #135 install

### The deploy-order claim in the last handoff was WRONG — and it bit

I wrote "deploy order does not matter." It does. The v2/v3 compatibility is
**one-directional**:

- **New server, old phone** — fine. A v2 push is accepted and simply does not
  reconcile `exerciseReports`, so an old client cannot wipe the backlog.
- **New phone, old server** — **400 on every push.** The phone sends
  `schemaVersion: 3`; a server pinned to 2 rejects it outright.

Installing the app before deploying the server therefore stalls sync with
`Server error 400`. Non-destructive — records stay `.pending` and retry — but
it looks alarming in Settings and it is entirely avoidable.

**Always deploy the Functions app before installing a client that bumps the
wire version.** The same trap is waiting for whoever bumps it to v4.

## Test state — and a correction to the previous baseline claim

| Suite | Result |
|---|---|
| Swift unit | superseded — see the current table above |
| Azure Functions (jest) | **172 pass** |
| MCP server (vitest) | **60 pass** |
| XCUITest | **flaky — see below** |

**The previous handoff's claim that "a non-zero exit is a real regression" does
not hold for the UI suite tonight.** Three runs on this machine:

- Full suite, my tree: 8 UI failures
- 15-test subset, **unmodified HEAD**: 1 failure (`testLongExerciseNameDoesNotBreakLayout`)
- Same subset, my tree: 2 failures — and `testLongExerciseNameDoesNotBreakLayout` **passed**

The failing sets do not overlap across runs on either tree, and most failures are
`Failed to synthesize event: Neither element nor any descendant has keyboard
focus`. That is flakiness in this environment, not a regression from these
commits. **Do not treat a UI-suite failure as a regression without running the
same subset against a clean worktree** — that comparison is what settled it, and
it takes about five minutes.

The unit suite remains a hard gate: it is deterministic and green.

## Notes for whoever picks this up

- **Schema V3 is taken.** #110 (nutrition) planned to use V3 and now needs V4
  plus its own `MigrationStage`. I commented on the issue.
- The wire/model field is `detail`, not `body` as issue #135 wrote it — `body`
  reads badly next to SwiftUI's `View.body`.
- `ReportStatus.acknowledged` deliberately counts as **open**. Acknowledged work
  is still outstanding; only `.resolved` leaves the backlog, in the repository,
  the Home count, and the server's default query.
- Reports can be resolved from the app (swipe on the Reports list) as well as
  over MCP. A backlog you can only clear from another device is one you stop
  trusting.
- **#127 is not superseded by this.** That is the heavy evidence path — sealed
  local diagnostic bundles, depends on #126. This is the lightweight synced
  channel. They meet at `.bug`: a report could later carry a #127 bundle ID.

## Older material, still true

**`app.keyboards` is empty on Evan's iPhone even with the keyboard onscreen.**
Resolved 2026-08-07; four `KeyboardDismissalTests` had been failing on device
and passing on the simulator. The app was correct the whole time — the query
was wrong.

A diagnostic dump with a weight field focused showed:

```
keyboards.count = 0     keys.count = 12     fieldHasFocus = true
Other, identifier: 'keyboard'      <- container is type Other, not Keyboard
    Key '1' … Key 'Delete'         <- a full decimal pad, plainly present
Button, label: 'Next keyboard', value: English (US)
```

The keyboard is exposed as an **`Other` element with identifier `"keyboard"`**
rather than as a `Keyboard`-type element, so `app.keyboards.count > 0` is
unsatisfiable while `app.keys` returns everything. The `Next keyboard` button
shows a third-party keyboard is installed, which is what differs from the
simulator.

Use `app.isSoftwareKeyboardVisible` and `app.waitForKeyboardToDisappear()` in
`UITestHelpers.swift`, never `app.keyboards.count`, or these tests will fail on
device forever.

Two earlier explanations were asserted and were both wrong — a hardware
keyboard (nothing is paired) and SwiftKey suppressing the keyboard (the system
decimal pad renders fine). Neither survived a look at the actual hierarchy.
**Dump the hierarchy before theorising about a UI test failure.**

## What Phase 1 changed (#123, #124, #125, and #121's ordering half)

`isFinished` was a **stored one-way Bool** that nothing ever reset, and an
`onChange` on it was the *only* trigger for the summary sheet. `endWorkout()`
lived solely in that sheet's Done button, and the sheet had no
`interactiveDismissDisabled`. Swipe it away and you stayed inside a workout that
was already saved and synced, with a Finish button that could never present
anything again — while each further tap silently re-stamped `completedAt`,
re-saved, re-bumped `timesPerformed` and re-ran PR detection.

The circle was structural: `endWorkout()` nils `activeWorkoutVM`, tearing down
the view that owned the sheet, so presenting the summary *required* postponing
the exit. The fix hands the receipt to `AppState` as a
`WorkoutCompletionSummary` presented over Home, making the two independent.

`isFinished` remains as a **derived** property, so its nine existing assertions
keep their meaning. The hazard was the stored one-way flag doubling as the sole
presentation trigger, not the name.

Post-commit work (`timesPerformed`, PR detection) now runs in a tracked
`postCommitTask`; join it with `awaitPostCommitWork()`, the same idiom as
`awaitPendingSave()`. Several E2E tests were passing only through incidental
main-actor ordering and now join explicitly.

**#132 was found and deliberately not fixed:** `HistoryListView` loads behind
`if vm == nil`, so `loadWorkouts()` runs once per launch and the History tab
serves a stale list — finish a workout and it's absent until you pull to
refresh. Different surface; would have widened the PR past Phase 1.

## What shipped previously

Installed to Evan's iPhone 2026-07-29 ~21:30, from `9e2213c`.

Four gym-session complaints, and what actually caused each:

| Complaint | Cause |
|---|---|
| Many "Done" buttons, none working | `ToolbarItemGroup(placement: .keyboard)` declared **inside** `SetRowView`, so every visible row contributed one to the same keyboard region, each clearing only its own `private @FocusState` |
| `0` in every weight box; typing 40 gave `040` | `Binding<Double>` with `set.weight ?? 0` — nil rendered as the literal string `0`, and the `"0"` prompt was dead code. The model (`Double?`) and ViewModel already accepted nil; **only the view erased it** |
| Can't tell weight from reps | No column headers; no `accessibilityLabel` on either field |
| Timer blocked the screen | ~200pt opaque card in a `ZStack` over a scroll view reserving only `.padding(.bottom, 80)` |

Now: one screen-level `@FocusState` keyed on exercise+set UUID with a single
keyboard accessory bar (prev/next/Done); `Binding<Double?>` via the optional
`TextField` overload, so nil renders empty with the previous session as a grey
prompt; select-all on focus so editing `40` to `45` no longer yields `4045`; a
`Grid` with SET/PREVIOUS/WEIGHT/REPS headers, ≥44pt targets and a stacked
`LabeledContent` layout at accessibility type sizes; and the rest timer as a
compact `safeAreaInset` bar backed by a **screen-owned** `RestTimerSession`.

Also fixed while in these files: `removeSet` left numbering gaps (Set 1, Set 3);
a second tap on ✓ silently rewrote `completedAt` and restarted the timer (now
un-completes); accessibility identifiers collided across exercises, which is why
the UI tests needed `firstMatch`.

## Ghost adoption was built and deliberately cut — do not re-add naively

The plan called for empty fields that adopt the greyed previous value on ✓.
It was implemented, then removed after adversarial review.

**`WorkoutSet.weight` is `Double?` and nil already means bodyweight.** So
"adopt when nil" cannot distinguish "accept the ghost" from "I meant blank":
previous 80 kg × 8, user wants bodyweight × 12, leaves weight empty → logs
**80 kg × 12**, silently. It also broke `LogSetTool`, which reads model fields
directly and would have logged visible ghosts as `weight=nil, reps=nil`.

Values are pre-written as before. The PREVIOUS column and prompts remain,
**display-only**, so a stale ghost is cosmetic rather than a wrong logged
weight. Revisiting this needs an explicit touched/cleared state or a bodyweight
control — and must be checked against the ChatTools write paths, which bypass
the ViewModel.

## Open follow-ups

- **#117** — `WorkoutDetailView.swift:135-144` writes `set.weight` directly to
  the model, bypassing the mutation API, so **history edits never sync**; also
  can't clear a value, and parses with non-locale `Double(String)`. Fix this
  before or with #122, which restyles the same row.
- **#122** — extend the set-row visual language to History and Home.
- **#120** — Coach `end_workout` can't reach the screen-owned `RestTimerSession`,
  so a Coach-ended workout still chimes and stays onscreen.
- **#121** — `persistMutation()` is documented as debounced but has no delay or
  cancellation check. (Untouched tonight — the ordering half was done in Phase 1.)
- **#132** — `HistoryListView` loads behind `if vm == nil`; the History tab
  serves a stale list until pull-to-refresh.
- **#118** Live Activities · **#119** app-wide accessibility.
- **#86** stays open: only three silent-failure items were taken. #94's auth
  comparison is now done; keychain, Bicep outputs and stale docs are untouched.

## Gotchas worth keeping

- `.searchable` exposes a **search field** (`app.searchFields`), not a text
  field — that was #96's whole cause. Its **Cancel button is not exposed to
  XCUITest on iOS 26.5**; clear the query instead. And an empty search field
  reports its **placeholder** as `value`, not `""`.
- The **iPhone 13 Pro Max simulator may not exist** and must be created, not
  substituted. iPhone 17 produces a false `ChatCoachTests` failure.
- Prefer `-destination 'platform=iOS,id=676B845C-62CA-52B1-A6DA-1FACF77CAC01'`
  over the device name — CLAUDE.md's string contains a typographic apostrophe
  that a straight quote will not match.
- Static typechecks are not a test run.
- The UI suite is flaky on this machine (2026-08-18). Compare against a clean
  `git worktree` before calling a UI failure a regression.
