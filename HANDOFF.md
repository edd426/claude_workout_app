# HANDOFF — First field feedback triaged (#136–#139)

Updated 2026-08-19 evening. Branch **`feat/exercise-reports`**.
The #135 report channel is installed, working, and **has already paid for
itself**: six reports came back from one gym session and four defects are now
filed. No app code has been changed yet — this handoff is the triage, not a fix.

## Do this first

1. **Restart Claude Code.** `infra/mcp/dist/` was rebuilt this session; the
   report tools are not in the running server until it re-spawns. Probe:
   `list_exercise_reports` returns six reports without a manual build first.
2. Start on **#136** (notes) — it is the only P1 and the only data-integrity
   item, and the user hit it twice in one session.

## What happened

The first real workout on 1.2.0 (build 2) — Lower B, 2026-08-19 — produced six
reports through the #135 channel. All six are still `open` in the backlog.

| Time | Category | Report | Outcome |
|---|---|---|---|
| 04:16 | bug | "What happened to the notes section on the exercises?" | **#136** |
| 04:46 | bug | Seated Leg Curl notes gone — "3 settings for this machine" | **#136** |
| 04:49 | formOrSetup | Split squat 10→8 reps | preference, not a defect |
| 04:54 | swapRequest | Ab Rollout → Machine Ab Crunch; "added it to the template and it didn't stick" | evidence on **#129/#130** |
| 04:56 | other | Want photo upload on reports | **not filed** — see below |
| 04:59 | other | Reps should auto-fill, not need ghost-text confirmation | **#137** |

## The finding that matters most — #136

Two independent defects produce one symptom, and the machine settings vanish
exactly where they are needed: standing at the machine, mid-set.

1. **`startFromTemplate` never copies `TemplateExercise.notes`.**
   `ActiveWorkoutViewModel.swift:247` passes `order` / `exercise` /
   `restSeconds` and nothing else.
2. **No UI renders or edits per-exercise notes during a workout.**
   `ExerciseCardView.swift` has zero references to notes.

**Both are older than 1.2.0** — `git log -S"notes: templateExercise.notes"` and
`git log -S"notes" -- …/ExerciseCardView.swift` are each empty, so neither line
ever existed. Do not go looking for the commit that broke it; there isn't one.
What changed is that the notes were previously arriving by another path (sync
inbound / MCP inbox — `InboxApplier.swift:339` is the only writer of template
notes) and no longer reach the session.

The data settles that the user's memory is right, not nostalgic:

- Lower B **2026-08-12** (`DCC20C31-…`): Trap Bar Deadlift `"Grip bar is down."`,
  Seated Leg Curl `"Ankle 4; Seat 4; Pivot 1"` ← literally the "3 settings"
- Lower B **2026-08-19** (`5743E0DD-…`): no notes on any exercise
- **Upper A** template carries per-exercise notes on 7 of 9; **Lower B**
  template has none — which is exactly why "other workouts have a notes section"

`SyncMapper` maps the field faithfully in both directions
(`:33` out, `:176` in), so this is a start-path and UI gap, never a sync bug.

## The trap waiting in #137

The reps request looks like a one-line revert of `9e2213c`. It is not.
**Adopt-on-empty was deliberately cut** because `nil` weight already means
bodyweight, so adopting the previous value logged 80kg for a bodyweight set.
Reinstating naive adoption reintroduces a data-corruption bug that was already
paid for once. The fix needs unset / explicitly-empty / entered as three
distinct states, and the red test must cover the bodyweight case first.

## Why #135's own tooling nearly hid all of this — #138

`list_exercise_reports` shipped in `infra/mcp/src/` with commit `4d41c20`, but
the MCP client runs `dist/src/server.js`, and `dist/` was a **stale build from
before that commit** — no `reports.js`, tools absent from the advertised list.
The feature looked shipped in the repo and did not exist in practice.

Fixed with `npm run build` (exit 0). The general hazard is unfixed: nothing
ties the running server to the committed source. This is the MCP-side analogue
of the `generate_project.py` versioning trap already in CLAUDE.md — a build
artifact whose staleness is invisible.

## Open question, not a conclusion — #139

The 2026-08-19 session has **no `completedAt`**; all 16 other synced sessions
have one. It may be nothing — walking away without tapping Finish is ordinary,
and this is a single occurrence. It is filed because Finish has form (#123,
#124, #125) and `finishWorkout` gained early-return paths in `0b17105` that
would silently no-op if `completionState` could be `.finished` on a workout
whose `completedAt` was never persisted.

Same session, unexplained: set timestamps are not monotonic with exercise order,
and two pairs are 0.68s and 5.9s apart — not real rest periods. Either the user
caught up at the end, or completing one set stamps its siblings. **Unresolved.**

## Deliberately not filed

The two feature requests from the same session are real but are not regressions,
and filing them was not what was asked:

- **Photo upload on reports** (04:56) — would let the coach judge whether a
  machine matches the exercise description. Note it argues for *creating* a
  custom exercise rather than reusing an ill-fitting one.
- **Search the exercise library from the report sheet** (inside the 04:54
  report) — the user could not name the replacement he wanted.

Both are worth issues. Ask before filing.

## State of the tree

No app code modified this session. The only change is
`infra/mcp/dist/` (rebuilt, and `dist/` is generated — check whether it is
tracked before committing). Branch `feat/exercise-reports` is otherwise as the
previous handoff left it.

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
