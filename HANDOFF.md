# HANDOFF — Finish reliability (Phase 1)

Updated 2026-08-07. The usability sprint's 6 commits are **pushed**. Phase 1 of
`WORKOUT_RELIABILITY_AND_TEMPLATE_PLAN.md` is on `fix/finish-reliability`.

## The test baseline — read this before judging any run

**`xcodebuild test` exits 0 on `fix/finish-reliability`:** 681 Swift Testing
(671 + 10 new), zero XCUITest failures, on iPhone 13 Pro Max / iOS 26.5.

The previous note that "a non-zero exit is now a real regression" was **wrong
for the first ~10 days of any month**, and cost a full investigation on
2026-08-07. `calendarHeatmap` seeded workouts at `today - 10 days` while
`CalendarViewModel.loadMonth()` fetches only the *current* month, so the light
workout fell into the previous month and vanished. The 2026-07-29 green run
happened on the 29th, which is why nobody saw it. Fixed in #131; the fixture is
now anchored to fixed days of the current month.

With that fixed the claim finally holds: **a non-zero exit is a real
regression.** The other traps still apply: never pipe `xcodebuild` through
`tail` without `set -o pipefail` (a background wrapper reported "exit code 0"
while xcodebuild had returned 65), and XCUITest failures print
`Test Case '-[...]' failed`, not Swift Testing's `✘`.

**Device runs need the phone unlocked.** A locked screen produces
`Waiting for the destination to become ready` and `** BUILD INTERRUPTED **`
before the build even starts — it looks like a toolchain problem and isn't.
The full device UI suite takes over 10 minutes; run it in the background.

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

## Open follow-ups from this sprint

- **#117** — `WorkoutDetailView.swift:135-144` writes `set.weight` directly to
  the model, bypassing the mutation API, so **history edits never sync**; also
  can't clear a value, and parses with non-locale `Double(String)`. Fix this
  before or with #122, which restyles the same row.
- **#122** — extend the new set-row visual language to History and Home (the
  Phase 3 that was cut).
- **#120** — Coach `end_workout` can't reach the screen-owned `RestTimerSession`,
  so a Coach-ended workout still chimes and stays onscreen.
- **#121** — `persistMutation()` is documented as debounced but has no delay or
  cancellation check.
- **#118** Live Activities · **#119** app-wide accessibility.
- **#86** stays open: only three silent-failure items were taken (insight
  dismissal, photo attach, exercise save). Keychain, auth comparison, Bicep
  outputs and stale docs are untouched.

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
