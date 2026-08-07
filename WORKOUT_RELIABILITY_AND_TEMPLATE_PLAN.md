# ClaudeLifter reliability, template reconciliation, and diagnostics — revised plan

Updated: 2026-08-07 (revision 2), after verifying the original plan's claims
against the source.

Status: Planning only. No implementation from this plan has started.

This file is intentionally at the repository root so Codex, Claude Code, and
other CLI agents can find and maintain the same implementation plan.

---

## Context

The original plan was written from a read-only MCP inspection of the cloud
mirror plus a source skim. It correctly identified that the workout persisted
and synced fine, so the failure had to be in the post-save UI transition — but
it labelled the cause "a strong hypothesis, not a proven root cause" and
sequenced a whole diagnostics subsystem in front of the fix.

**Reading the code closes that question.** The cause is proven, and the fix is
small. The plan is resequenced accordingly, and the diagnostics work is scoped
down to what would actually have caught this class of bug.

### Root cause — confirmed, not hypothesised

Three facts in the current source combine into a permanent trap:

1. `ActiveWorkoutViewModel.swift:9` — `var isFinished = false` is set to `true`
   at lines 462 and 479 and **is never reset anywhere in the codebase**
   (grep over `ClaudeLifter/`, `ClaudeLifterTests/`, `ClaudeLifterUITests/`).
2. `ActiveWorkoutView.swift:92-94` — the *only* trigger for the summary is
   `onChange(of: vm.isFinished) { if finished { showSummary = true } }`. An
   `onChange` on a one-way `Bool` fires exactly once per app run.
3. `ActiveWorkoutView.swift:298-312` — `appState.endWorkout()` is called *only*
   from `WorkoutSummaryView`'s Done button. `WorkoutSummaryView.swift` has no
   `interactiveDismissDisabled`, so the sheet is freely swipe-dismissable.

**The trap:** swipe the summary sheet down instead of tapping Done →
`showSummary = false`, `endWorkout()` never runs, `isFinished` stays `true`
forever. Every subsequent Finish tap re-enters `finishWorkout()`, which finds
`workout` still non-nil and `hasCompletedSets` still true, so it **re-stamps
`completedAt = .now`, re-saves, and re-runs PR detection** — while `onChange`
cannot fire again, so nothing appears. The user is stuck in a workout that is
already saved, and each tap silently corrupts `completedAt`.

Contributing defects found alongside:

- `ActiveWorkoutView.swift:82-83` — two `.sheet(isPresented:)` modifiers on the
  same view (summary + exercise picker). Unreliable in SwiftUI; explains
  "Finish right after adding an exercise did nothing".
- `finishWorkout()` has no in-flight guard, so concurrent taps can run
  overlapping saves and duplicate PR detection.
- `ActiveWorkoutViewModel.swift:470-478` — template bookkeeping and PR
  detection run *inside* the success path with `try?`, before `isFinished` is
  set. Slow or failing PR detection delays leaving the workout, and its failure
  is swallowed.
- `ActiveWorkoutViewModel.swift:459-464` — the empty-workout branch calls
  `cancelWorkout()` (nilling `workout`) then sets `isFinished = true`. The
  summary sheet then renders an empty `Group` with **no Done button** — another
  strand. Currently unreachable from the Finish button (it's `.disabled` unless
  `hasCompletedSets`) but reachable from any future non-UI caller.

### What the original plan got right, and what changed

Kept essentially intact: the product principles, the "actual performance is not
a template target" rule, the policy matrix, the change-set semantics, the
privacy prohibitions, the non-goals, and the cross-CLI handoff protocol. Those
are good and this revision does not relitigate them.

Changed, per decisions taken 2026-08-07:

| Original | Revised | Why |
|---|---|---|
| Phase 1 = diagnostics foundation, Phase 2 = Finish fix | **Phase 1 = Finish fix**, diagnostics after | Cause is proven; no trace is needed to find it |
| Phases 1+5+6 = full diagnostics, MetricKit, server upload | **Local only**: OSLog + signposts + ring buffer + bug button + share-sheet export | Server upload and MetricKit deferred; new privacy surface not yet earned |
| Phases 3-4 template reconciliation, undated | **Own sprint after Phase 1** | Needs a schema migration; see the V3 collision below |
| "Plausible symptom match… strong hypothesis" | Confirmed root cause with file:line | Evidence upgraded |

### Two facts the original plan missed

- **Schema version collision.** `App/AppSchema.swift` already defines
  `ClaudeLifterSchemaV1`/`V2` with a `ClaudeLifterMigrationPlan`. Open issue
  **#110** plans a **V3** for nutrition. Template provenance also needs a new
  version. Whichever ships second must be V4 — coordinate, or two branches will
  both claim V3 and the migration plan will silently mis-order. Memory note
  *"SwiftData stored property changes crash on-device"* applies directly here.
- **#81** proposes deleting ~3,400 lines of in-app AI surface. Adding a second
  large subsystem (diagnostics) to an app under consideration for shrinking is
  worth a deliberate call — hence the reduced diagnostics scope.

---

## Phase 0 — MCP parity and baseline

Verified at planning time (read-only):

- `claude mcp list` → `workout: … dist/src/server.js — ✔ Connected`.
- `codex mcp list` → **no `workout` entry**. Only `computer-use` and
  `node_repl`. The original plan's claim here is still accurate.
- Repo `.mcp.json` is `{"mcpServers": {}}`; secrets live in `~/.claude.json`.
- `git status`: clean except the untracked plan file. **6 commits unpushed**
  (`3456a2b` … `07aa630`) — `HANDOFF.md` says 5; it predates its own commit.
- Test baseline per `HANDOFF.md`: `xcodebuild test` **exits 0**, 671 Swift
  Testing pass, zero XCUITest failures. A non-zero exit is now a real
  regression.

Remaining work:

- [ ] Register `workout` with Codex via `codex mcp add` (its own registry —
      do not edit Claude Code's). Env: `FUNCTIONS_BASE_URL`,
      `FUNCTIONS_API_KEY`, from user-level config only.
- [ ] Verify in a fresh Codex session: `health` first, then `list_workouts`,
      `get_workout`, `list_templates`, `get_stats`.
- [ ] Re-run the full suite to reconfirm the baseline before touching code.

**Never** commit a config containing the API key, and never let it reach plan
text, diagnostics, or command output.

---

## Phase 1 — reliable, idempotent Finish  *(do this first)*

Smallest change that ends the trap. Target: one focused PR.

### ViewModel — `ActiveWorkoutViewModel.swift`

Replace `isFinished: Bool` with an explicit, identifiable completion state:

```swift
enum CompletionState {
    case active
    case finishing(attemptID: UUID)
    case saved(WorkoutSummaryPayload)   // Identifiable
    case failed(Error)
}
```

- [ ] **Idempotency.** Entering `finishWorkout()` while `.finishing` or
      `.saved` returns immediately. Track the in-flight `Task` so repeated taps
      join it rather than starting a second save. `completedAt` is set **once**
      per successful attempt — never re-stamped.
- [ ] **Deterministic pending-save resolution.** `persistMutation()`
      (line 241) cancels and replaces `pendingSave`. Before the authoritative
      save, either `await awaitPendingSave()` or cancel it — a draft save must
      never land after completion. Note `saveDraft()` (line 426) *deletes* the
      workout when it has no exercises; it must not run post-completion.
      Related: **#121** (`persistMutation` documented as debounced but isn't).
- [ ] **One critical transaction.** `workoutRepository.save(workout)` is the
      only thing that must succeed. On success, publish the summary payload and
      clear active state **immediately**.
- [ ] **Post-commit work.** Move template `timesPerformed`/`lastPerformedAt`
      bookkeeping and `prDetectionService.detectPRs` out of the critical path
      into observable follow-up. Replace the `try?` at lines 474 and 477 with
      explicit handling — log failures, never reopen the workout.
- [ ] **Retry.** A failed critical save leaves the workout intact and
      `.failed`, with an enabled Retry.
- [ ] Fix the empty-workout branch (lines 459-464) so it ends the workout
      directly instead of routing through a summary that cannot exist.

### View — `ActiveWorkoutView.swift`

- [ ] Drive the summary from `.sheet(item:)` on the completion payload, not
      `onChange` of a `Bool` (delete lines 92-94).
- [ ] **Call `appState.endWorkout()` as soon as the critical save succeeds**,
      not from the summary's Done button. The summary becomes a receipt
      presented over Home; dismissing it any way — Done, swipe, or failure to
      present — is harmless.
- [ ] Collapse the two sibling `.sheet(isPresented:)` (lines 82-83) into one
      presentation router, or move the summary to a root-level destination.
- [ ] Disable Finish and show progress while `.finishing`.

Keep `performAfterFlushingFocusedField` (line 364) exactly as-is — its 10 ms
yield is load-bearing for the last numeric edit and is already covered by tests.

### Tests (red first, per `.claude/rules/tdd.md`)

Unit — extend `ClaudeLifterTests/ViewModelTests/ActiveWorkoutViewModelTests.swift`:

- Double and triple `finishWorkout()` → exactly one save, one PR-detection
  call, `completedAt` unchanged after the first.
- Failing PR service / failing template save → workout still completed.
- Failing critical save → `.failed`, workout intact, retry succeeds.
- A `persistMutation` in flight at Finish time cannot overwrite the final save.

Four existing tests assert `vm.isFinished == true`
(`ActiveWorkoutViewModelTests.swift:145,412,437,462`) plus five in
`E2ETests/`. These migrate to the new state — **update them, do not delete**;
lines 412 and 437 ("UI should still dismiss") are exactly the post-commit
resilience this phase formalises.

UI — `ClaudeLifterUITests`:

- Finish, **swipe the summary away**, and confirm Home is underneath and the
  workout is not resumable. *This is the regression test for the reported bug.*
- Rapid triple Finish → one completed workout in history.
- Finish immediately after dismissing the exercise picker.

**Gate:** full suite exits 0 on iPhone 13 Pro Max / iOS 26.5, then install to
the device and finish one real workout before moving on.

---

## Phase 2 — diagnostics, local only

Scoped to *"add local bug-report bundle"*. No server endpoint, no MetricKit,
no Blob retention — those move to Non-goals below.

- [ ] Structured `Sendable` event type: timestamp, monotonic sequence, app
      session ID, correlation ID, subsystem, name, severity, outcome, screen,
      scene phase, safe IDs, duration, bounded metadata.
- [ ] Mirror to `os.Logger` with subsystem/category separation. **No OSLog or
      MetricKit usage exists in the app today** — this is greenfield.
- [ ] `os_signpost` intervals around Finish, SwiftData saves, sync, PR
      detection, and (later) template reconciliation.
- [ ] JSONL ring buffer written through a dedicated actor, off the main actor.
      Rotate at the earlier of 72 h or 10 MB. Excluded from backup and from
      workout sync. Appropriate file protection.
- [ ] "There's a bug" in the active-workout menu and Settings. Seal the trace
      *before* prompting. Capture the prior 15 min plus a bounded state
      snapshot, then offer an optional note and consented screenshot. Show a
      report ID. Review / share-sheet export / delete.
- [ ] Instrument the Finish path with one correlation ID per attempt, covering
      the ten transitions listed in the original plan §Phase 1.

**Never record:** API keys, auth headers, Keychain values, server secrets, chat
prompt/response bodies, exercise photos, HealthKit samples, arbitrary TextField
contents, or full SwiftData dumps. Prefer stable IDs in the continuous trace;
human-readable workout state only inside an explicitly created report.

Bundle: `manifest.json`, `events.jsonl`, `state.json`, optional
`screenshot.png`, optional `user-note.txt`. `state.json` is a bounded
projection — workout/template IDs, counts, completion state, pending
persistence/sync state, last sync revision, recent surfaced errors — not a
database export. The report ID plus workout ID is enough to cross-check the
cloud record over MCP.

**Acceptance:** a bundle is produced with no network access; it reconstructs a
Finish transition; disk stays within the documented cap; automated redaction
tests pass.

---

## Phase 3 — template baseline and change detection  *(separate sprint)*

Unchanged in substance from the original plan §Phase 3, with additions:

- Store source template ID **and revision/`lastModified`** on the `Workout`.
  Today `Workout` carries only `templateId` (`Models/Workout.swift:7`) and
  `WorkoutExercise` carries no provenance at all — every field below is new.
- Give copied workout exercises a source `TemplateExercise` ID; mid-workout
  additions have none.
- Persist the planned baseline: order, set count, target reps, rest seconds,
  template cue/notes.
- Record explicit structural intents (add / remove / reorder) separately from
  inferred outcomes such as "left incomplete".
- Crash-resumed workouts (`init(resuming:)`, line 104) must retain provenance.
- Migration-safe defaults for existing workouts; no retrospective
  reconciliation of old history.

**Schema gate.** This is a new `VersionedSchema` in `App/AppSchema.swift`.
Coordinate the version number with **#110**'s nutrition V3 — second one in is
V4. Test the migration on a device-realistic store before shipping.

Pure, testable change-set service emitting only meaningful proposals: added
exercise, explicitly removed exercise, explicit reorder, planned set-count
change, explicit target-rep change, explicit default-rest change, explicit
template-cue change.

Rules: incomplete/skipped exercises are **not** removals; substitutions are not
inferred without explicit provenance; multiple changes apply as one coherent
update; a template modified externally since workout start raises a conflict
rather than being overwritten.

**Never** diff logged weights/reps against template defaults — auto-fill
(`AutoFillService`, and `startFromTemplate` lines 198-217) makes that
comparison meaningless.

Acceptance: the recorded 2026-08-07 `Upper A` session (two additions —
Leverage Chest Press, Leverage Shoulder Press; six template exercises left
incomplete) yields **two additions and zero automatic removals**. A skipped
exercise alone yields nothing. Crash/resume yields the same change set.

---

## Phase 4 — post-workout review and policies  *(same sprint as 3)*

Policy matrix unchanged from the original plan — everything structural defaults
to **Ask after workout**; logged weight/reps, completed/skipped sets, temporary
rest-timer adjustments, and session notes are **Never**; template usage
metadata is **Automatic**. "Always" still means *apply after completion*, never
mutate the template mid-workout.

- [ ] Nonblocking card on the summary/Home, only when a meaningful change set
      exists. Review changes / Keep template unchanged.
- [ ] For additions: Keep for this workout / Add to template / Replace an
      existing exercise. Never guess a replacement from an incomplete exercise.
- [ ] Per-change selection, concise final diff before Apply, optional
      "Remember for this kind of change".
- [ ] Settings → Workout & Templates to review and reset remembered policies.
      Note `Views/Settings/` is a single `SettingsView.swift` today.
- [ ] Ad-hoc workouts offer Save as new template instead of update.
- [ ] Apply: re-fetch the template, detect revision conflict, validate every
      exercise reference, one local transaction, normalise ordering, call
      `recordChange()`, queue normal phone-authoritative sync.

Acceptance: the completed workout is safe before any prompt appears; declining
leaves the template byte-for-byte unchanged; a failed apply cannot hide or
undo the workout.

---

## Verification

Run from the repo root. Simulator must be **iPhone 13 Pro Max / iOS 26.5** —
create it if missing, never substitute (an iPhone 17 run produced a false
`ChatCoachTests` failure).

```bash
set -o pipefail
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' test
```

- Baseline and post-change: **exit 0**, 671+ Swift Testing pass, zero XCUITest
  failures. Non-zero is a real regression — the old "known four" note is dead.
- XCUITest failures print `Test Case '-[...]' failed`, not Swift Testing's `✘`.
- Never pipe through `tail` without `set -o pipefail`.
- Static typecheck is **not** a test run.

Device run (highest fidelity; prefer the ID over the name — `CLAUDE.md`'s
device string contains a typographic apostrophe):

```bash
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS,id=676B845C-62CA-52B1-A6DA-1FACF77CAC01' test
```

Manual gate for Phase 1 — on the phone, log one workout, tap Finish, then
**swipe the summary away instead of tapping Done**. Home must be underneath and
the workout must not be resumable. That single gesture is the whole bug.

Cloud cross-check (read-only, `health` first): `list_workouts` and
`get_workout` should show one completed record with a `completedAt` that
matches the first Finish tap. **Never run MCP write tools against production
as part of diagnosing this.**

---

## GitHub issues

None of the 35 previously open issues covered this work. Filed 2026-08-07:

| # | Title | Labels | Phase |
|---|---|---|---|
| [#123](https://github.com/edd426/claude_workout_app/issues/123) | Finish strands the user in a completed workout when the summary sheet is swipe-dismissed | `bug` `P1-high` `workout` `data-loss` | 1 |
| [#124](https://github.com/edd426/claude_workout_app/issues/124) | Finish is not idempotent — repeated taps re-stamp `completedAt` and re-run PR detection | `bug` `P1-high` `workout` | 1 |
| [#125](https://github.com/edd426/claude_workout_app/issues/125) | Move template bookkeeping and PR detection out of the Finish critical path | `tech-debt` `P2-medium` `workout` | 1 |
| [#126](https://github.com/edd426/claude_workout_app/issues/126) | Local structured diagnostics: OSLog, signposts, and a bounded JSONL ring buffer | `enhancement` `tech-debt` `P2-medium` | 2 |
| [#127](https://github.com/edd426/claude_workout_app/issues/127) | "There's a bug" — user-created local diagnostic bundles with share-sheet export | `enhancement` `P2-medium` | 2 |
| [#128](https://github.com/edd426/claude_workout_app/issues/128) | Persist template provenance on workouts (new `VersionedSchema`) | `enhancement` `P2-medium` `workout` `templates` | 3 |
| [#129](https://github.com/edd426/claude_workout_app/issues/129) | Post-workout template change detection service (`TemplateChangeSet`) | `enhancement` `P2-medium` `workout` `templates` | 3 |
| [#130](https://github.com/edd426/claude_workout_app/issues/130) | Post-workout template review UI and remembered reconciliation policies | `enhancement` `ux` `P2-medium` `workout` `templates` | 4 |

Adjacent existing issues, cross-linked with comments on filing:

- **#117** — history edits bypass the mutation API and never sync. Same
  reliability family as #123–#125.
- **#120** — Coach `end_workout` leaves the rest timer running. Same completion
  path; fix *with* Phase 1, not separately.
- **#121** — `persistMutation()` isn't actually debounced. **Blocks #124.**
- **#110** — nutrition schema V3. **Version collision with #128**; second one
  in must be V4.
- **#81** — AI surface deletion; context for keeping the diagnostics scope
  small.

---

## Non-goals

Unchanged from the original plan, plus three now explicitly deferred:

- Rewriting the workout data model or sync architecture.
- Updating templates from ordinary logged weights/reps.
- Automatically removing skipped exercises from templates.
- Always-on screen recording or session replay.
- Using MCP write tools to patch user data while diagnosing.
- **Deferred:** MetricKit crash/hang integration (original Phase 6).
- **Deferred:** the diagnostics Functions endpoint, Blob payload storage, and
  30-day server retention (original Phase 5 §Delivery).
- **Deferred:** continuous or automatic diagnostic upload of any kind.

---

## Cross-CLI handoff protocol

Any agent taking a phase should:

1. Read `CLAUDE.md`, `HANDOFF.md`, `CONTINUATION.md`, and this file.
2. Inspect `git status` and preserve unrelated changes. **6 commits are
   currently local and unpushed.**
3. Use the workout MCP server for cloud facts; call `health` first and stay
   read-only unless the user explicitly asks for a mutation.
4. Implement one phase or tightly related slice at a time.
5. Update checkboxes and append a dated entry to the log below.
6. Record the exact tests run and their results. A typecheck is not a test run.
7. Never place credentials or personal diagnostic payloads in commits.

---

## Decision and progress log

- **2026-08-07** — Plan created from repository inspection, source flow,
  platform guidance, and read-only MCP data. No app code, MCP configuration, or
  user data modified.
- **2026-08-07 (revision)** — Root cause **confirmed** in source: swipe-dismiss
  of the un-guarded summary sheet leaves the one-way `isFinished` latched, so
  `endWorkout()` never runs and later Finish taps silently re-stamp
  `completedAt`. Resequenced: Finish fix promoted to Phase 1, diagnostics
  reduced to local-only, MetricKit and server upload cut to Non-goals, template
  reconciliation moved to a separate sprint. Recorded the schema-V3 collision
  with #110 and the unreachable empty-workout summary branch. Still no code,
  configuration, or data modified.
- **2026-08-07** — Issues #123–#130 filed against this plan; #110, #117, #120,
  and #121 cross-linked. Phase 1 (#123–#125, with #120 and #121) is the next
  work to start.
