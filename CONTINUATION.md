# ClaudeLifter — Deep refactor session handoff

Last active: 2026-04-24. Work paused by user; app is on-device and behaving.

## Session state

**15 commits on `main` ahead of `origin/main`, all local, nothing pushed yet.**
Run `git push origin main` when you want to publish.

Test baseline: **534 unit tests + 11 `WorkoutFlowTests` UI tests** — all green
in the iPhone 16e (iOS 26.2) simulator. Zero fatal errors, zero failures.

Plan file (can archive when you're satisfied):
`/Users/eddelord/.claude/plans/i-d-like-you-to-ticklish-hickey.md`

## What got fixed this session

### Critical (on-device bugs the user reported)

| Commit | What it fixed |
|---|---|
| `58a55a4` | **"Start Workout" button dead** — TemplatePreviewView now dismisses itself before triggering the workout start so the HomeView root-swap is visible. |
| `962a161` | **Coach silent after create_template** — system prompt now mandates a narration after every tool result; `loadPreferences()` finally wired into `ChatView.task`. |
| `476ca9a` | **BuildInfo lied about build date** — now reads the executable's mtime (link time), not `Date()` at first access (launch time). |
| `559064b` | **`lastModified` not auto-updated on mutations** — new `SyncableModel` protocol + `recordChange()` helper, called from every mutation site. Kingpin fix for sync LWW. |
| `4336b4a` | **Settings said Opus, Coach used Haiku** — `SettingsManager` exposed on `DependencyContainer` and threaded into `ChatViewModel`. |
| `b78e9c2` | **Model switch didn't live-update Coach header** — `SettingsManager` converted to `@Observable` with stored properties. |
| `4894747` | **Two `SettingsManager` instances across the app** — `SettingsView` now binds to the DI container's instance, not a freshly-constructed one. |
| `4894747` | **Multiple stale in-progress workouts piling up** — `startWorkout()` deletes prior in-progress rows; `saveDraft()` refuses to save empty-exercise ghosts. |
| `4894747` | **Coach can now close out workouts** — new `end_workout` tool with `finish / discard / cleanup_stale` actions. |

### Polish

| Commit | What it fixed |
|---|---|
| `a7b3f80` | Schema-migration fallback, keyed-string `SyncStatus`, `NWPathMonitor` leak (your WIP, committed cleanly). |
| `9efb787` | Active AI model shown in Coach header; tool-chain depth-5 stop becomes visible message; `ExerciseDetailView` `.onAppear → .task`; surfaced `ExerciseLibraryViewModel` filter errors. |
| `3f0b31d` | Concurrent `sendMessage` guard + input disabled while streaming; `persistMessage` logs errors; `WorkoutSummaryView` no longer nests NavigationStack inside a sheet. |
| `4336b4a` | Coach markdown paragraph breaks preserved (`inlineOnlyPreservingWhitespace`); keyboard dismissal on Settings; "Cancel" → "Exit" + smart skip-dialog-when-empty; proactive insights toggle in Settings. |
| `b78e9c2` | `AIModel` includes version (`Opus 4.7`, not just `Opus`); removed redundant keyboard "Done" button. |
| `4894747` | `###` headers preprocessed to `**bold**` before rendering; Coach system prompt includes model identity so the AI can answer "which model are you?"; system prompt tells Claude to avoid `#`-headers. |

### Test infrastructure

| Commit | What it added |
|---|---|
| `559064b` | `LastModifiedPropagationTests` — 9 tests, every mutation path asserts `lastModified` + `.pending` syncStatus. |
| `476ca9a` | `BuildInfoTests` — 2 tests, guards against regression to runtime `Date()`. |
| `c0826c8` | `PaginationBoundsTests` — 3 tests using the **real** `SwiftDataWorkoutRepository` against 200+ fixtures to guard the #71 class of memory bugs. |
| `c742557` | Killed pre-existing SwiftData context-reset crashes in E2E teardown via `[weak self]` Tasks + new `awaitPendingSave()`. |
| `46c678b` | Rewrote `testFinishWorkoutWithNoSetsCompleted` to match real UX (Finish correctly disabled until at least one set). |

## What's left — follow-up work

Nothing is broken; these are genuinely "next sprint" items, roughly in priority order.

### High value

1. **Coach prompt caching (~90% cost savings available).** `ChatViewModel.buildSystemPrompt` is called per message. Add `cache_control: ephemeral` to the static portion, build once per conversation, and measure with `usage.cache_read_input_tokens`. *(Explicitly deferred this session.)*
2. **Device UI test provisioning.** `xcodebuild test -destination platform=iOS,...` failed with `CoreDeviceError 1002 "No provider was found."` — the test bundle needs its own provisioning profile separate from the app. Fix in Signing & Capabilities for the `ClaudeLifterUITests` target in Xcode. Once fixed, the 60-ish UI tests can run on-device too, not just simulator.
3. **Dynamic model list.** `AIModel` is a hardcoded enum — every new Anthropic release needs a rebuild. Accept arbitrary model strings with validation at first use.
4. **Azure sync end-to-end on device.** Bicep infra + Functions exist under `/infra` but haven't been deployed/tested against the real phone. Issue #64 (CI/CD) is still the only open GitHub issue.

### Medium

5. **`SetRowView` state/data race.** Local `@State` copies SwiftData model values and writes back via `.onChange`. External mutations (auto-fill completion, sync pull, tool call) during edit can clobber/revert the user's typed weight or reps. Refactor to VM-mediated updates.
6. **`RestTimerService` singleton in DI.** Each `RestTimerOverlayView` currently instantiates its own. Move to `DependencyContainer` to prevent any regression of #46.
7. **Remaining `try?` silent failures.** `HomeView.insight.markAsRead`, `ActiveWorkoutViewModel.saveDraft`, `ExerciseDetailView.handlePhotoSelection`, `ClaudeLifterApp.populateImageURLsIfNeeded`. Replace with explicit error logging or a user-surfaced banner.
8. **`@State var vm = VM(...)` pattern elsewhere.** `ActiveWorkoutView` and some others — change to the `@State var vm: VM?` + `.task` init pattern (as `HomeView` now does) to prevent re-init on parent redraws.
9. **`navigationDestination(for:)` refactor.** `HomeView.templateList` still uses closure-based `NavigationLink`. Value-based navigation would let Coach's `start_workout` tool actually push the view programmatically instead of just flipping state.

### Low / test-infra

10. **Replace remaining tautological mocks.** `MockWorkoutRepository.recentSets` etc. — where a SwiftData-in-memory repo can stand in, delete the mock. Most tests that use these will work unchanged.
11. **UI tests that don't assert.** `ChatCoachTests`, `HistoryCalendarTests`, etc. launch + tap but don't assert the outcome. Rewrite with real assertions.
12. **Multi-conversation chat switching test.** Missing from the suite — seed 50 messages in conversation A, switch to B, back to A, assert no bleed.

## Useful commands

```bash
# Full baseline (unit + key UI flow)
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 16e' test \
  -only-testing:ClaudeLifterTests \
  -only-testing:ClaudeLifterUITests/WorkoutFlowTests

# Just the new regression suites
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,OS=26.2,name=iPhone 16e' test \
  -only-testing:ClaudeLifterTests/LastModifiedPropagationTests \
  -only-testing:ClaudeLifterTests/ChatViewModelTests \
  -only-testing:ClaudeLifterTests/BuildInfoTests \
  -only-testing:ClaudeLifterTests/PaginationBoundsTests

# Build & install on the plugged-in phone
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS,id=00008110-001E1D8114F3801E' build
xcrun devicectl device install app \
  --device 00008110-001E1D8114F3801E \
  ~/Library/Developer/Xcode/DerivedData/ClaudeLifter-hksekbwiejlwszcjbxmhraxgbzaf/Build/Products/Debug-iphoneos/ClaudeLifter.app

# Publish when ready
git push origin main
```
