# ClaudeLifter

Native iOS strength-training tracker with Claude AI coaching. Single-user personal app.
Full specification: @SPEC.md

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Swift 6 / SwiftUI (iOS 17+) |
| Local Storage | SwiftData |
| AI | Anthropic API via SwiftAnthropic SDK (configurable models) |
| Cloud (Phase 2) | Azure Cosmos DB (Free Tier) + Blob Storage + Functions |
| MCP (Phase 3) | TypeScript + @modelcontextprotocol/sdk |
| Exercise Data | free-exercise-db (800+ exercises, public domain JSON) |
| Infra-as-Code | Bicep |

## Architecture

```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
│         (Workout, Exercises,            │
│          Chat, History, Settings)       │
└──────────────┬──────────────────────────┘
               │ binds to
┌──────────────▼──────────────────────────┐
│     ViewModels (@Observable)            │
│     @MainActor, protocol-based DI      │
└──────┬───────────────────┬──────────────┘
       │                   │
┌──────▼──────┐    ┌───────▼─────────────┐
│ Repositories│    │     Services        │
│ (protocols) │    │ ┌─────────────────┐ │
│             │    │ │ AnthropicService│ │
│ SwiftData   │    │ │ AutoFillService │ │
│ impls       │    │ │ RestTimerService│ │
│             │    │ │ ExerciseImport  │ │
└──────┬──────┘    │ └─────────────────┘ │
       │           └──────────┬──────────┘
┌──────▼──────┐               │
│  SwiftData  │        ┌──────▼──────┐
│  (Local)    │        │ Anthropic   │
└─────────────┘        │ API (proxy) │
                       └─────────────┘
```

## Current Phase

**Phases 1–2 complete. Phase 3 all but Live Activities.** The app is deployed and in
daily use; work is now issue-driven, not phase-driven — **the open GitHub issues are
the real backlog**, not this list.

Phase 2 — Cloud Sync + Images: **done and deployed** (Bicep infra; Functions API;
sync DTOs + `SyncMapper`; `NetworkService`; `SyncManager`; Anthropic key proxied via
`ProxiedAnthropicService`; `CalendarHeatmapView`; `PhotoCaptureView` + SAS upload;
`InsightRepository`; Settings server URL + sync status).

Phase 3 — MCP + Advanced AI: **done** except Live Activities. MCP server ships read
tools (#79) and inbox-based writes (#88); proactive insights, 15 chat tools incl.
template/program generation, `PRDetectionService`, and `ChartsView` all exist.
Also shipped beyond the original plan: body-weight tracking + HealthKit (#80),
backup export/import (#72), crash recovery (#75), rest-timer notifications (#77).

- [ ] **Live Activities** — rest timer on Lock Screen / Dynamic Island. No
      `ActivityKit` usage in the codebase; the only unstarted phase item.

> **SPEC.md §7 and §11 are stale on sync.** They describe bidirectional
> last-write-wins with `/sync/pull` and `/sync/push`. That design was replaced in
> #78 by a **one-way snapshot mirror**: the phone is authoritative, pushes complete
> state, and the server reconciles by deleting anything absent. `syncPull.ts` and
> `syncPush.ts` still exist but no client calls them (#92 tracks removal). Trust
> `infra/functions/src/functions/syncSnapshot.ts` and `infra/MCP_WRITE_PATH.md`
> over the SPEC here.

## Development Methodology

**Red-Green TDD.** Tests are written FIRST using Apple's Swift Testing framework.
See `.claude/rules/tdd.md` for the full workflow.

## Key Conventions

- **Simulator**: match the real device — Evan carries an **iPhone 13 Pro Max on iOS 26.5.x**. Do not substitute whatever simulator ships newest; on 2026-07-27 an iPhone 17 run produced a false `ChatCoachTests` failure that did not reproduce on the real hardware. The previously documented `iPhone 16e` no longer exists in Xcode. If the destination is missing, **create it** rather than substituting:
  `xcrun simctl create "iPhone 13 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-26-5`

- **Typechecking is not testing.** A clean `tsc`/`swiftc` parse says nothing about behavior — on 2026-07-27 two rounds of write-path work typechecked cleanly and still failed the simulator suite. Run `xcodebuild test` before claiming a change works, and beware piping it through `tail` without `set -o pipefail`, which masks the real exit code.

- **Architecture**: MVVM with `@Observable` ViewModels
- **DI**: Protocol-based. Every service/repository has a protocol. Tests inject mocks.
- **Testing**: Swift Testing (`@Test`, `#expect`) — NOT XCTest (`XCTAssert*`)
- **SwiftData**: `isStoredInMemoryOnly: true` for test containers. Never access `ModelContext` from Views/ViewModels — go through repositories.
- **Concurrency**: `@MainActor` on ViewModels. `async/await` for services.
- **Style**: Swift API Design Guidelines. No force unwraps in production code.

See `.claude/rules/` for detailed guidance on each area.

## Commands

```bash
# Build
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' build

# Test
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' test

# Test on the real device (highest fidelity; UI tests run in-memory, real data untouched)
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS,name=Evan DeLord'\''s iPhone' test

# Skills (when available)
/build    # Build the project
/test     # Run all tests
/tdd      # Start a TDD cycle for a feature
/phase    # Show current phase progress
```

## Agent Ownership

| Agent | Owns | Tests |
|-------|------|-------|
| `data-models` | Models/, Repositories/, Services/AutoFill*, Services/ExerciseImport*, Services/Sync/, Services/ImageUpload*, Resources/ | ModelTests/, RepositoryTests/, ServiceTests/AutoFill*, ServiceTests/ExerciseImport*, ServiceTests/Sync*, ServiceTests/ImageUpload* |
| `ui-viewmodels` | Views/, ViewModels/ (except Chat*), App/, Services/RestTimerService | ViewModelTests/ (except Chat*) |
| `ai-chat` | Services/Anthropic*, Services/Proxied*, Services/ChatTools/, ViewModels/Chat*, Views/Chat/ | ServiceTests/Anthropic*, ServiceTests/Proxied*, ViewModelTests/Chat* |
| `reviewer` | Read-only review, no code changes | — |
| `infra` | infra/ (Bicep IaC + Azure Functions TypeScript) | infra/functions/tests/ |

Dependency order: `data-models` first → `ui-viewmodels` + `ai-chat` in parallel → `reviewer` last.
See `.claude/AGENT_COORDINATION.md` for coordination rules.

## Project Structure (Planned)

```
ClaudeLifter/
├── App/                     # Entry point, tab bar, app state
├── Models/                  # SwiftData @Model classes
├── Repositories/            # Protocol + SwiftData implementations
├── Services/                # Business logic, APIs, ChatTools/
├── ViewModels/              # @Observable classes
├── Views/                   # SwiftUI views by feature tab
│   ├── Workout/
│   ├── Exercises/
│   ├── Chat/
│   ├── History/
│   ├── Templates/
│   └── Settings/
├── Resources/               # exercises.json, Assets.xcassets
└── Utilities/               # Extensions, helpers
ClaudeLifterTests/
├── Helpers/                 # Test container factory, mocks, fixtures
├── ModelTests/
├── ViewModelTests/
├── ServiceTests/
└── RepositoryTests/
```

## Key Files

- `HANDOFF.md` — **Read this first if it exists.** Pickup state for work in flight: what is verified vs assumed, what remains, and how to check it.
- `infra/MCP_WRITE_PATH.md` — MCP inbox write-path design (#88): why direct Cosmos writes cannot work, and why exercises are referenced by `externalId` not UUID
- `SPEC.md` — Full product specification (features, data model, architecture, phasing)
- `.claude/rules/` — Code style, TDD, SwiftData, AI service patterns
- `.claude/agents/` — Agent definitions with file ownership
- `.claude/skills/` — Custom slash commands (/build, /test, /tdd, /phase)
- `.claude/AGENT_COORDINATION.md` — Agent team coordination rules
- `.mcp.json` — MCP servers (empty for Phase 1; Phase 3 adds workout MCP server)
