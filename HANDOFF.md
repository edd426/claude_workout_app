# HANDOFF — Exercise reports (#135), ready to install

Updated 2026-08-18, end of evening session. Branch **`feat/exercise-reports`**,
two commits, **not pushed**, branched off `docs/fix-stale-build-recipes`.

## Do this first in the morning

1. **Decide the version number** (see "The version bump is unresolved" below) —
   this is the one thing I could not settle without you.
2. Install to the phone. The interesting part is not the feature, it is the
   **V2→V3 schema migration against your real data**. A new `@Model` is exactly
   the change that has crashed on-device before. The migration is additive and
   lightweight, and the simulator's empty store proves nothing about it.
3. If the migration is fine, file a report from a real exercise mid-workout and
   check it survives a sync. Full end-to-end needs the Azure deploy below.

## What landed

**#135 — in-workout exercise reports.** A flag in the exercise card's overflow
menu, in the active-workout toolbar, and in exercise detail. Pick a category
chip, type a sentence, Send. Everything else — `exerciseExternalId`, workout,
template, the set state at that moment, app and iOS version — is captured, not
asked for. Reports mirror to Cosmos with the rest of the snapshot and are
readable over MCP as `list_exercise_reports`, closed out with
`resolve_exercise_report`.

The design decision worth remembering: **there is no target picker.** Context is
something the app knows, not something you choose in a gym. The category chip is
the only input, and it tells the reader which captured context matters.

**#104 — custom exercises were never pushed.** `Exercise` is the one mirrored
type with no per-record `syncStatus`, so `hasPendingChanges` could not see it; a
custom exercise sat unpushed until some unrelated change triggered a snapshot.
Now signalled from the repository. The durable marker also became a pair of
generation counters, because the old boolean was cleared unconditionally after
the network await — a create landing mid-request was absent from the payload
*and* had its only signal wiped.

**#94** constant-time API key compare. **#93** the three force-unwrapped
`Calendar.date` calls.

## The version bump is unresolved — your call

Memory says the convention is 3-part semver from 1.1.0, bumped in six pbxproj
spots before every device install. **The repo does not match that.**
`generate_project.py` hardcodes `MARKETING_VERSION = '1.0'` and
`CURRENT_PROJECT_VERSION = '1'`, and it *regenerates* `project.pbxproj` — so any
bump made directly in the pbxproj is wiped the next time a file is added and the
generator runs (which happened several times tonight). Either the convention
lapsed, or bumps were being made in a file that does not survive.

I did not guess a number: I cannot see what is installed on the phone, and
picking 1.1.0 could be a *downgrade*. Decide the number, then change it in
**`generate_project.py`** (not the pbxproj) so it survives regeneration.

## Azure deploy is required for the MCP half

The app half works offline. The MCP half does not, until:

- **Bicep** — new Cosmos container `exerciseReports` (`infra/modules/cosmos.bicep`)
- **Functions** — new `GET /api/reports`, plus snapshot v3 and the new inbox op
- **MCP server** — `npm run build` in `infra/mcp` for the two new tools

Until the container exists, a v3 push will report a failure for that collection
and the client will keep retrying — it will not corrupt anything.

Wire contract v3 **accepts v2 pushes on purpose**: the server deploys
independently of the app, and a phone still on the old build knows nothing about
reports. Reading its push as "there are no reports" would delete the whole
backlog. Absent from the contract means untouched, not empty. So deploy order
does not matter.

## Test state — and a correction to the previous baseline claim

| Suite | Result |
|---|---|
| Swift unit (`-only-testing:ClaudeLifterTests`) | **717 tests, 94 suites, exit 0** |
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
