# HANDOFF — #136 and #137 fixed, unreleased; install is the next step

Updated 2026-08-19 late evening. Branch **`feat/exercise-reports`**.
**1.3.0 (build 4) is committed and unreleased — it is not on the phone yet.**
Both gym-feedback fixes are in this one build; build 3 was never installed.

## Do this first

1. **Install 1.3.0 (4) and do a Lower B.** The Settings footer showing
   `1.3.0 (4)` is the proof it landed. Neither fix is verified on real hardware
   — only by 727 unit tests and a simulator build.
2. **#136 probe** — on Seated Leg Curl, tap ⋯ → *Add a note…* →
   `Ankle 4; Seat 4; Pivot 1` (recovered from the 2026-08-12 session). It
   should then appear on every future workout containing that exercise,
   including a Lower A or an ad-hoc one.
3. **#137 probe** — add Ab Crunch Machine mid-workout (it is still not in the
   template — see #129/#130). Its three sets should arrive with reps already
   filled from last session and **weight empty**. Weight staying empty is the
   fix working, not a bug.
4. Then resolve the three acknowledged reports, and pick from
   "What to look at next" below.

## What #136 turned out to be

The issue's own proposed fix would not have worked, and the data is what
settled it. Copying `TemplateExercise.notes` into the session is correct but
inert here: **the Lower B template has no notes on any exercise.** The
`"Ankle 4; Seat 4; Pivot 1"` note lived on the *2026-08-12 session*, and
nothing in the app writes `WorkoutExercise.notes` — only `SyncMapper` and the
MCP inbox do. It arrived from outside and died with that session. 08-05 had
none; 08-19 had none.

So a session-scoped note typed at the machine would have vanished again the
following week and produced the same report.

**The note now lives on the library `Exercise`.** It describes the machine, so
it follows the exercise into every workout whichever template that workout came
from. Evan's words: *"if I make a new workout with the same exercise, I want the
same note to appear with it."*

- inline on `ExerciseCardView` — a note behind a tap is not read mid-set
- edited from a **sheet**, deliberately not inline: the workout screen owns one
  `@FocusState` keyed on `SetEntryFieldID` with a weight/reps accessory bar, and
  a free-text field in that hierarchy would have to join or fight it
- read-only section on `ExerciseDetailView`
- the template→session copy is **kept** — a template note is a per-plan cue, a
  different thing, and renders as its own line
- `ActiveWorkoutViewModel` gained an optional `exerciseRepository`; all three
  inits and all four construction sites pass it. **If it is nil the note is
  written to the model and never saved** — that is the failure mode to look for
  if a note does not stick.

### The hole this leaves — #140

The note is *also* stamped onto `WorkoutExercise.notes`, on purpose. Bundled
exercises are excluded from sync (`SyncManager:331`, `:405`) **and** from backup
(`BackupService:7-8`), so the library note is **device-local**: lost on
reinstall, not restored by a backup restore, invisible to the Coach and MCP.
The workout record is the copy that travels. #140 covers carrying user data on
bundled exercises properly, and it is a `schemaVersion` 4 change — so
**deploy the Functions app before installing that client** (see below).

## Report backlog state

Three reports are now **acknowledged**, not resolved — `CD42B832` (04:16) and
`5B380FF1` (Seated Leg Curl) for #136, and `79EEC980` (04:59) for #137. The
fixes exist but are not on the phone. Acknowledged still counts as open;
resolve them once the install confirms them.

The remaining three:

| Time | Category | Report | Where it goes |
|---|---|---|---|
| 04:49 | formOrSetup | Split squat 10→8 reps | preference, not a defect |
| 04:54 | swapRequest | Ab Rollout → Machine Ab Crunch | evidence on **#129/#130** |
| 04:56 | other | Photo upload on reports | **#141** |
| 04:59 | other | Reps should auto-fill | **#137 — fixed, acknowledged** |

The 04:54 report is now corroborated: both the 08-05 and 08-12 Lower B sessions
contain **Ab Crunch Machine at order 4**, and the template still does not. He
has added it twice and it has never stuck. That is #129/#130's whole case.

## What #137 turned out to be

Not a revert of `9e2213c`, and not really about ghost text. The hole was
**`addExercise`**: an exercise added mid-workout gets three sets with no values
and a ghost map that is display-only, so nothing was ever written. The other
two creation paths already pre-wrote values (`startFromTemplate` per set index,
`addSet` from the last previous), which is why only mid-workout additions were
affected — and Ab Crunch Machine is added mid-workout every single session.

The second example in the issue is **not a bug**: Barbell Ab Rollout set 2 with
`reps: 10` and no weight is correct. It is a bodyweight exercise.

`repsDecidedByUser: Set<UUID>` is the third state — *unset* (adopt) vs
*decided-empty* (persist nil) vs *entered* (leave alone). It is recorded in
`updateSetReps` even when the value is unchanged, because clearing an
already-nil field is still a decision. Completed sets are never touched.

**Reps only. Weight is never adopted**, because `weight == nil` already means
bodyweight — that is the cut-once bug, and it stays cut. The bodyweight case is
the first test in the file.

Known and deliberate: `repsDecidedByUser` is transient, so a crash/resume
re-adopts reps on untouched empty sets. Conservative for reps; it would not be
for weight. Making it durable costs a `schemaVersion` bump and is not worth it.

## Why #135's own tooling nearly hid all of this — #138

`list_exercise_reports` shipped in `infra/mcp/src/` with commit `4d41c20`, but
the MCP client runs `dist/src/server.js`, and `dist/` was a **stale build from
before that commit**. The feature looked shipped in the repo and did not exist
in practice. Fixed with `npm run build`; **verified this session** — a restarted
client returned all six reports with no manual build. The general hazard is
unfixed: nothing ties the running server to the committed source.

## Open question, not a conclusion — #139

The 2026-08-19 session has **no `completedAt`**; all 16 other synced sessions
have one. It may be nothing — walking away without tapping Finish is ordinary,
and this is a single occurrence. It is filed because Finish has form (#123,
#124, #125) and `finishWorkout` gained early-return paths in `0b17105` that
would silently no-op if `completionState` could be `.finished` on a workout
whose `completedAt` was never persisted.

Same session, unexplained: set timestamps are not monotonic with exercise order,
and two pairs are 0.68s and 5.9s apart — not real rest periods. **Unresolved.**

## The two feature requests — now filed

- **#141 photo upload on reports** (04:56) — lets the coach judge whether a
  machine matches the exercise description. The second half of that report is
  the real point: it argues for *creating* a custom exercise rather than
  reusing an ill-fitting one. Offline capture is not optional; the gym is where
  connectivity is worst, and a report that fails because an upload failed is
  worse than one with no photo.
- **#142 search the library from the report sheet** (inside the 04:54 report).
  He wrote `"Machine Ab Crunch"`; the library exercise is **"Ab Crunch
  Machine"**. A resolved `externalId` would make a swap request actionable by
  #129/#130 instead of a name someone has to guess at.

## What to look at next

Ranked by what the field data actually supports:

1. **#129/#130 — the template never learns.** Double-corroborated now: Ab
   Crunch Machine appears at order 4 in **both** the 08-05 and 08-12 Lower B
   sessions and is still not in the template. He has added it at least twice
   and it has never stuck, which is also why #137 bit him at all. This is the
   highest-value gap in the backlog.
2. **#117 — history edits never sync.** `WorkoutDetailView.swift:135-144`
   writes `set.weight` straight to the model, bypassing the mutation API, so
   the record never re-queues as `.pending`. Data integrity, and it pairs with
   #122 which restyles the same row.
3. **#139 — the missing `completedAt`.** Still an open question, not a
   conclusion. See below.
4. **#140 — bundled-exercise user data never leaves the phone.** New this
   session, and it now has real data behind it: every note he writes on a
   bundled exercise is device-local.
5. **#138 — nothing ties `infra/mcp/dist/` to the committed source.** A
   `prepare`/`postinstall` build, or a CI check that rebuilds and diffs, closes
   it cheaply. The staleness is invisible until a tool silently does not exist.
6. **#132 — the History tab serves a stale list** until pull-to-refresh. Small,
   known, and annoying immediately after finishing a workout.

Not a defect, but he asked for it: the 04:49 report says he moved **Split Squat
10 → 8 reps** for strength. That is a template edit (`4DE7A259-…`,
`defaultReps: 10`) nobody has made. **Ask before writing to his template.**

## State of the tree

Branch `feat/exercise-reports`, four commits ahead of where the triage left it:
`14a3a6d` (triage recorded), `2b729e4` (#136), `fc1c37e` (handoff),
`9a9b56b` (#137 + build 4). Unpushed. `infra/mcp/dist/` is rebuilt and
untracked.

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
| Swift unit (`-only-testing:ClaudeLifterTests`) | **727 tests, 94 suites, exit 0** (2026-08-19, with #136 + #137) |
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
