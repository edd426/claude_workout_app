# ▶ START HERE — 2026-09-26: 1.7.0 (9) is INSTALLED, Functions DEPLOYED, PR #157 MERGED

Branch state: everything is on **`main`** (`76e4042`, merge of PR #157; #145 shows
as merged by the same commit). The cloud branch `claude/clever-mayer-sb25i3` and
`feat/exercise-reports` are fully contained in main and can be deleted.

What was verified on the Mac today, in order:

- **Build** clean on the iPhone 13 Pro Max simulator. No compile fixes were needed
  for the blind-written Swift.
- **Swift unit suite: 832 tests, 104 suites, exit 0.** XCUITest 68/70; the two
  failures (`ChatCoachTests.testSendButtonEnabledAfterTyping` keyboard focus,
  `ExerciseLibraryTests.testSearchForExercise` dropped keystroke) are outside this
  work and passed on an isolated rerun. `KeyboardDismissalTests` 7/7 including the
  new caret-at-end test.
- **Functions jest 230/230, MCP vitest 112/112** locally as well as in CI.
- **Functions deployed** (`npm run clean && npm run build && func azure functionapp
  publish func-workout-prod --typescript`, then `az functionapp restart`). Live
  probe: `GET /api/images/sas?path=reports/{uuid}.jpg&mode=upload` → 200,
  `other/x.jpg` → 400, health 200.
- **1.7.0 (9) installed** via `devicectl` from a `generic/platform=iOS` build.
  The first two installs timed out at "Enabling developer disk image services"
  (`kAMDMobileImageMounterExistingTransferInProgress`): the phone is on iOS 26.6.2
  and the DDI transfer over Wi-Fi takes a few minutes. A retry loop every 60s
  succeeded on the third attempt. **Not yet confirmed by Evan**: the Settings
  footer should read `1.7.0 (9)`.
- **MCP `dist/` rebuilt** for `get_report_photo`; the Claude Code MCP client still
  needs a restart to see the new tool.

Workout-MCP chores from §5 below, all done 2026-09-26 and **queued as inbox
operations** (they land on the next phone sync; two need approval on the phone):

- `4905a7d0` **Lower B: Trap Bar Deadlift 3×5 → 3×10** — needs approval.
- `8e0075a9` **Friday Pump: Hammer Curls note** now reads "Dumbbells, neutral grip…"
  (the old note said "Replaces Barbell Curl", which read as an instruction) — needs approval.
- `744C6C83` resolved with the per-exercise rest explanation.
- Acknowledged against **#156**: `02384B15 F1F61A87 42C5E2AF 999E3289 A21CD30E 0974E343`.
- Acknowledged as shipped-in-1.7.0, resolve after the §4 gym probes:
  `07B1AD96 8FF8C6D5 31A4983B 2A40BB7C E7A4E5F7`.
- Acknowledged pending approval: `0537E988 E26BBFAA`.

Not done: the leverage-pulldown custom exercise (`0974E343`) waits on #156's photo
inventory; `999E3289` / `A21CD30E` are not yet saved as training preferences.

Local-Mac note: `main` had six stale local-only commits from the 1.1.0 era
(`d28d660..a6e92ea`, all still on `feat/sol-prefill-notes-recentmax`); local main
was reset to `origin/main`.

Next: the §4 gym probes, then resolve the five shipped reports. After that the
backlog is #153 (batch approval screen), #150, #154, #156.

---

# ▶ START HERE — picking this up on the Mac

**Branch `claude/clever-mayer-sb25i3`, PR #157.** It was written in a Linux cloud
session on 2026-09-25 while Evan was travelling, and **nothing Swift in it has
ever been compiled.** Do the steps in this order and stop at the first one that
fails.

```bash
git fetch origin && git checkout claude/clever-mayer-sb25i3 && git pull
python3 generate_project.py        # should be a no-op; if the pbxproj changes, commit it
```

1. **Build.** `xcodebuild -scheme ClaudeLifter -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' build`
   Compile errors are the most likely first failure. Fix them in place. Where a
   review flagged a risk, it is listed under "Most likely to break" below.
2. **Unit + UI tests** (`set -o pipefail`; see §1 below). The baseline on `962c5b0` was exit 0 with 791 Swift tests. Anything red is this branch's fault until shown otherwise. Fix the code, not the test, unless the test itself is wrong.
3. **Deploy the Functions app** (§3). Photo uploads get a 400 until this is done.
4. **Install 1.7.0 (9)** on the phone. The Settings footer must read `1.7.0 (9)`.
5. **Workout-MCP chores** (§5): resolve and acknowledge reports, Trap Bar Deadlift → 10 reps, the leverage pulldown, the Hammer Curls note. The cloud session had no MCP, so none of these is done.
6. **Gym probes** (§4), then resolve the reports that pass.

**Most likely to break** (all flagged by a read-only review; none confirmed):
- `SetRowView.FocusWithCaretAtEnd`: XCUITest may call the set fields "not hittable". The fallback is to delete `.allowsHitTesting(isFocused)`, then check on the device that the caret still lands at the end.
- `ReportSheetView` / `CameraPicker`: new UIKit bridging, and the camera does not exist in the simulator. Only a device exercises it.
- Swift 6 strict concurrency in `ReportPhotos.swift` (`@MainActor` protocols; `UIGraphicsImageRenderer` used from a nonisolated static).

**Who owns the branch.** The cloud session that wrote this watches #157 hourly.
Once commits it did not write appear on the branch, it treats the Mac session as
the owner and **does not push**. Push freely.

Prompt to paste into Claude Code on the Mac:

> Read HANDOFF.md (the START HERE block first), check out `claude/clever-mayer-sb25i3`,
> and work through the steps in order. Fix compile and test failures on this branch,
> commit and push each fix, and stop before deploying or installing so I can confirm.

---

# HANDOFF — 2026-09-25: the 13-report batch (branch `claude/clever-mayer-sb25i3`)

Built from `feat/exercise-reports` @ `962c5b0` (1.6.0 (8)) in a **Linux cloud
session with no Xcode**. Read the first section before anything else.

## 1. Nothing Swift in this branch has been compiled or run

Every Swift change and every Swift test here was written blind. The tests were
written first, per the repo's TDD rule, but **none has been seen to fail or to
pass**. A read-only review pass traced every hunk and found no compile
errors; its other findings are fixed in the "Address review findings" commit.
That does not replace a compiler.

**First action, before installing anything:**

```bash
set -o pipefail
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' test 2>&1 | tee /tmp/test.log
```

The baseline on `962c5b0` was exit 0 (791 Swift tests, 99 suites). A non-zero
exit here is this branch's fault until shown otherwise. New suites to watch:
`WorkoutAutoFinishPolicyTests`, `AutoFinishTests`, `TemplateNoteEditingTests`,
`ReportPhotoTests`, `ReportSheetPhotoTests`, the new `ImageUploadServiceTests`
cases, and the UI tests `KeyboardDismissalTests.testTappingFilledRepsFieldPutsCaretAtEnd`
and `testEmptyWeightFieldDoesNotPrefixTypedValueWithZero`. The second is an
existing test changed here: it relied on select-all.

The TypeScript half **was** run here: Functions jest **230/230**, MCP vitest
**112/112** (after `npm run build`), both exit 0.

## 2. What changed, by report

| Report | What it asked | What this branch does | Commit |
|---|---|---|---|
| `07B1AD96` | Auto-finish a forgotten workout after ~3h; tell me when I'm back; duration = first set → last set | `WorkoutAutoFinishPolicy`: 3h after the **last logged set**. The recorded window is trimmed to first→last logged set. It runs when the app returns to the foreground (active workout screen) and on Home for leftover drafts. The receipt says it was automatic. A workout with nothing logged is never auto-finished (#69/#75) | `d5a3fde` |
| `8FF8C6D5` | Cursor at the end of the reps box on tap | The first tap on an unfocused set field focuses it programmatically, so UIKit leaves the caret at the end. Replaces select-all. **Trade-off chosen: typing now appends** (15 + "2" = 152). Applies to weight too | `e7850e8` |
| `31A4983B` | AI notes take space, aren't editable | The template (Coach) note is collapsed to one line; tap to expand; "Edit template note" there and in the ⋯ menu | `16a79cc` |
| `E26BBFAA` | Hammer Curls note says barbell | The bundled library has Hammer Curls as **dumbbell**; the barbell wording is in the Friday Pump **template note**. It is now editable in-app. The edit goes to this workout's copy, and the finish summary offers it for the template (#129/#130 review, behind its revision check) | `16a79cc` |
| `42C5E2AF`, `2A40BB7C` (+ `E7A4E5F7`) | Photos on reports | #141 end to end: camera/library on the report sheet; kept offline; uploaded on sync to `reports/{id}.jpg`; `photoURL` set only after upload; MCP `get_report_photo` returns the image | `23c2959`, `a7a6c03`, `1ab4192` |
| `F1F61A87` | Make an issue for a gym-photo inventory | **#156** filed; also rolls up `02384B15`, `0974E343`, `A21CD30E`, `999E3289`. **Not** added to Reminders — this session has no Reminders access | — |

Also fixed while in there:

- **The post-workout template review (#130) could never Apply.** `runPostCommitWork` bumps `timesPerformed`, and with it the template's `lastModified`, *before* change detection runs. So every template workout's review showed "This template changed somewhere else" and Apply threw `.conflict`. This predates the branch and the E26BBFAA flow depends on it. Detection now re-anchors on the post-bookkeeping revision, but only when nothing else touched the template since the start; a real mid-workout edit is still a conflict. Both cases are pinned in `TemplateNoteEditingTests`.
- `SASResponse` required a `blobUrl` field that the server has never sent, so every real decode failed. Nothing called the upload path before #141, and `MockNetworkService` skips decoding, so no test saw it.

## 3. Deploy order for #141

1. **Functions:** `cd infra/functions && npm run clean && npm run build && func publish <app> --typescript`, then `az functionapp restart` (see the 2026-08-31 gotchas below). Until this is live the SAS endpoint answers `reports/…` with 400.
2. **MCP:** `cd infra/mcp && npm run build`, then restart the MCP client so it picks up `get_report_photo`.
3. **Phone:** already bumped to **1.7.0 (9)** in `generate_project.py` and the regenerated project; build and install. The Settings footer should read `1.7.0 (9)`.

The order is not critical. A phone that ships first keeps its photos locally
and retries every sync; `photoURL` stays nil until an upload succeeds.
**NSCameraUsageDescription is new.** If the camera kills the app on first use,
the Info.plist key did not make it into the build.

## 4. Gym probes

| Probe | Expected |
|---|---|
| Tap a filled reps box on its **left** edge, press ⌫ once | The last digit goes. No second tap needed |
| Start a workout, log a set, background the app for 3h+ (or leave it overnight), reopen | The summary appears over Home, headed by "Finished automatically after 3 hours…", with Duration = first set → last set |
| Force-quit mid-workout, reopen after 3h+ | Same, from the Home path; the Resume card does not linger |
| Friday Pump → Hammer Curls | The template note is one grey line with a chevron; tap expands; "Edit template note" → fix "barbell" → Finish → the summary offers the cue change for the template → Apply |
| Finish any template workout you changed (added an exercise, edited a note) | The summary's template review has **no** orange "changed somewhere else" warning, and Apply succeeds. Before this branch it always warned and always failed |
| ⋯ → Report a problem… → Take Photo | The thumbnail shows; Send works **offline**; after the next sync with signal, the report row shows a 📷 and `get_report_photo` over MCP returns the picture |

## 5. Needs the workout MCP — not possible from this session

This session had no workout MCP connection, so **no report was resolved and no
template was changed.** Each item below needs a Claude Code session on the Mac:

- `0537E988` **Trap Bar Deadlift → 10 reps** in Lower B (default reps; "high reps to avoid straps").
- `0974E343` **Wide-Grip Lat Pulldown → a leverage pulldown.** free-exercise-db has none (checked: only cable variants), so create a custom "Wide-Grip Leverage Lat Pulldown" and swap it into Upper A. Tracked in #156.
- `E26BBFAA` **Friday Pump Hammer Curls note:** fix "barbell" → dumbbells. Either over MCP or in-app with the new editor + finish-summary Apply.
- `744C6C83` **Answer, no change:** rest is per exercise per template (`TemplateExercise.defaultRestSeconds`, default 90s). The Coach-built templates set 60s on some isolation moves, which is why some rests are 1:00 and others 1:30. There is no global setting. The #144 target line on each card shows it (`Target 3 × 12 · 60s rest`). Resolve with that explanation, or acknowledge if a global default is wanted.
- `02384B15`, `F1F61A87`, `42C5E2AF`, `999E3289`, `A21CD30E` → acknowledge against **#156**. `999E3289` (grip past ~70 kg) and `A21CD30E` (one squat rack) are also worth saving as training preferences.
- After install and the probes pass: resolve `07B1AD96`, `8FF8C6D5`, `31A4983B`, `2A40BB7C`, `42C5E2AF` (photo half), and `E7A4E5F7` (#141 half; #142 is still open). `D82C516F` stays acknowledged (#152).

## 6. Known gaps and deliberate choices

- **Your own note still overwrites the session copy.** `updateExerciseNotes` stamps the user's machine note onto `WorkoutExercise.notes` (pinned by an existing test). Editing your note therefore hides that session's template note, and the finish summary then proposes your note as the template cue. This predates the branch and was left alone because #150/#151 are redesigning notes. It is the next thing to settle there.
- **Not done: a single note that both you and the Coach write.** That changes what the MCP write path targets; it belongs with #150/#151.
- **Auto-finish of a *resumed* draft does not bump the template's `timesPerformed`.** A resumed VM has no `template`. This matches Resume → Finish today.
- **First launch after install:** any leftover in-progress draft whose last logged set is 3h+ old will auto-finish and show its summary. That is the feature working, but expect it.
- One idle draft is auto-finished per pass (only one receipt can be on screen). Older ones surface on the Resume card and finish on the next launch or return to the app.
- **If the set-field UI tests report "not hittable":** `FocusWithCaretAtEnd` in `SetRowView.swift` turns off hit testing on the unfocused TextField *and* covers it with a tap overlay. The review expects XCUITest's accessibility hit test to ignore that, but it has not run. The fallback is to delete `.allowsHitTesting(isFocused)`: the overlay alone should still take the first tap. Check on device that the caret still lands at the end if you do.
- A camera photo is JPEG-encoded at full size, then downscaled, on the main actor. Expect a brief hitch after the shutter. It is a one-off per report, so it was left alone.
- The view-level triggers (scene phase on Home and the workout screen), the camera and PhotosPicker have **no automated test**.

---

# (2026-08-31) NEXT PRIORITY WAS #141 — now implemented on `claude/clever-mayer-sb25i3`, see above

Evan, end of 2026-08-31: "It's easier to show you what's wrong as an image."
Labeled P1-high, design pointers commented on the issue. Watch the #91 SAS
path validation — reports need their own blob path family added deliberately,
not by loosening the exercises/{uuid}.jpg regex. #142 pairs with it. After
that: #153 (batch approval screen), #150 (decide-at-the-change), #154
(report-action discoverability + fixedInVersion auto-resolve).

---

# HANDOFF — 2026-08-31, evening: 1.6.0 (8) INSTALLED, server DEPLOYED

- **1.6.0 (8) is on the phone** — Evan confirmed the Settings footer. Installed
  via `devicectl` after `xcodebuild` against the device failed with "developer
  disk image could not be mounted" (phone moved to iOS 26.6.1 since the last
  install; build with `-destination 'generic/platform=iOS'` and install the
  .app with `xcrun devicectl device install app --device 676B845C-…`). Open
  Xcode once with the phone unlocked to re-prepare the device.
- **Functions deployed and verified**: health 200, `sync/pull` → 404 (dead
  endpoints really gone), `DELETE /api/inbox/{id}` live (401 unauthenticated).
  **Two deploy gotchas, both cost a redeploy tonight:** (1) `func publish`
  needs `--typescript` (cannot infer the runtime); (2) `tsc` never deletes
  compiled output for removed sources — stale `syncPull.js`/`syncPush.js` in
  `dist/` deployed and kept the routes alive until `npm run clean && npm run
  build` + publish + **`az functionapp restart`** (registrations survive a
  plain redeploy). That is #138's staleness bug in Functions form: consider a
  clean step in a predeploy script.
- Evan approved the five queued template changes on-phone; the serial,
  Home-blocking dialog experience prompted **#153** (batch pending-changes
  screen with real diffs, one sync per batch; closes #147's no-diff prompt).

---

# HANDOFF — 2026-08-31 cheap-delegate batch

Updated 2026-08-31. Branch **`feat/exercise-reports`**, still PR #145. Three
commits landed today via Haiku/Sonnet delegates with a Fable review pass
(outcome log: `docs/agent-task-log-2026-08-31.md`):

- `1130978` — #90/#91/#94: chat proxy model/max_tokens allowlist
  (`ALLOWED_MODELS`, `MAX_TOKENS_CAP` app settings, defaults fit the app's
  three models and the 14096-token extended-thinking path), SAS path locked to
  `exercises/{uuid}.jpg`, auth via constant-time compare + 30s-cooldown
  throttle (the delegate's version locked out permanently; reworked).
- `8988b6d` — #148: `DELETE /api/inbox/{id}` (terminal statuses only,
  etag-conditioned) + MCP `delete_inbox_operation` (all-or-nothing batch).
- `0d9b69d` — report-sheet UX: keyboard Done bar, Home-toolbar report button
  (general report, no exercise attached), note-prefill pinned by regression
  test (couldn't reproduce the complaint — watch report DA879E08).

**Verified on the integrated branch:** Swift unit suite exit 0 (791 tests,
99 suites), Functions jest exit 0, MCP vitest 85/85 (needs `npm run build`
first — dist staleness guard).

**Not deployed / not installed.** Wire version unchanged, so order doesn't
matter this time, but the server fixes need `func publish` and the UX fixes
need a device install (bump `generate_project.py` first — minor, this is
feature work). #90/#91/#94/#148/#117/#93 closed on GitHub as committed.

## Follow-up session, same day — everything above that needed Evan is done

- **#92 landed** (`588fd1b`): the mystery uncommitted deletions were neither
  Evan's nor agent-cost-optimization-02's; intent matched the delegate's
  finished commit, so it was cherry-picked over them (plus the `types.ts`
  cleanup and the current v2/v3 header). Jest 203/203. Issue closed.
- **Five template approvals are waiting on the phone** (Evan approved the
  content in-session; #147 means the prompts show only a count): Lower A
  Leg Press → Single-Leg Press custom; Lower B Ab Rollout → Ab Crunch
  Machine; Friday Pump variety rework + generalized note; Upper A and
  Upper B notes recording the **day swap — Upper B takes Monday (no barbell
  bench), Upper A with bench moves to Wed/Thu** (the bench-hogger report).
- **Interview done** → issue **#150**: template changes prompt at the moment
  of change; drift only when repeated 2+ sessions; explicit Ask/Always/Never
  per category in Settings. Supersedes #130's review-first direction.
- Issues filed: **#151** session-scoped "why" notes, **#152** body-weight
  graph + goal rate. GitHub closes done: #90 #91 #92 #93 #94 #117 #148.
- **Report backlog fully answered** — every open/acknowledged report now has
  an accurate status and resolution text queued to sync.

## Inbox ops enqueued today (land on next phone sync)

Single-Leg Press creation; report status changes — resolved: Spotify
(C7F9B7E5, investigated: app has no audio session, chime is a notification),
the stale "awaiting install" trio (79EEC980, 5B380FF1, CD42B832), Split Squat
2×8 (990C04B4); acknowledged with next-build notes: 8A8E7366, DA879E08,
A590AD71, A67CF295.

---

# HANDOFF — 1.5.0 is installed

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
- **#148** inbox operations cannot be deleted, so failed ones accumulate forever
- **#147** *Review Change* shows no change — the inbox approval prompt is a
  `confirmationDialog` whose whole message is an exercise **count**, so a
  one-number edit is indistinguishable from a full rewrite

## 1.5.0 (7) — installed 2026-08-20

**#146 is fixed**, the server half is deployed, and the build is on the phone
(Release, launched, data intact: mirror still revision 380 with all 17 workouts,
5 templates and 6 reports). No schema migration in this one — a plain upgrade
install. The mirror revision did **not** advance, which is correct: nothing was
dirty, so no push was due.

- The reports list filter is now Outstanding / Open / Acknowledged / Resolved /
  All — the same vocabulary `list_exercise_reports` uses, so the phone and the
  AI agree about what is left. Default is Outstanding (open + acknowledged).
- The home card counts only `.open`, with acknowledged shown beside it:
  "3 open · 3 awaiting install" rather than "6 open reports".
- **Reopening works end to end** — MCP tool, Functions validation, inbox
  applier. All three had refused it deliberately; #136's inert fix is what
  changed the call. Swipe a report for Resolve / Acknowledge / Reopen.
- `resolve_exercise_report` takes `ids` for a batch, validated all-or-nothing.

No schema change — nothing here adds a stored property. Nutrition still takes V5.

**Litter I made:** inbox op `f4c9187b` is a validation probe with a bogus report
id, now terminal in `failed` alongside the three July `deleteTemplate` ones. It
will never reach the phone, and it cannot be removed — filed as **#148**.

### Check when you next open the app

- Reports → the filter chip top-right reads **Outstanding**, and switching it to
  Acknowledged shows exactly the three answered reports
- The home card reads **3 open · 3 awaiting install**, not "6 open reports"
- Swipe a report: Resolve / Acknowledge / Reopen / Delete

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
