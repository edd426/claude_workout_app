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

**Phase 2 — Cloud Sync + Images** (Phase 1 complete: 166/166 tests passing)

- [ ] Azure Bicep infrastructure (Cosmos DB, Storage, Function App)
- [ ] Azure Functions API (sync/pull, sync/push, images/sas, chat proxy, insights, health)
- [ ] Model updates (syncStatus/lastModified on WorkoutTemplate, ProactiveInsight, TrainingPreference)
- [ ] Sync DTOs + SyncMapper (Codable model ↔ JSON conversion)
- [ ] NetworkService (URLSession wrapper with auth)
- [ ] SyncManager (NWPathMonitor, pull/push, BGAppRefreshTask, last-write-wins)
- [ ] API key proxy (Anthropic key moves from device to Azure Function)
- [ ] Calendar heatmap (monthly view with workout intensity shading)
- [ ] Photo capture (PhotosPicker + Azure Blob upload via SAS tokens)
- [ ] InsightRepository (ProactiveInsight CRUD)
- [ ] Settings updates (server URL, sync status indicator)

See SPEC.md §7 for Azure Backend details, §11 for Phase 2 scope.

## Development Methodology

**Red-Green TDD.** Tests are written FIRST using Apple's Swift Testing framework.
See `.claude/rules/tdd.md` for the full workflow.

## Key Conventions

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
  -destination 'platform=iOS Simulator,name=iPhone 16e' build

# Test
xcodebuild -scheme ClaudeLifter \
  -destination 'platform=iOS Simulator,name=iPhone 16e' test

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

- `SPEC.md` — Full product specification (features, data model, architecture, phasing)
- `.claude/rules/` — Code style, TDD, SwiftData, AI service patterns
- `.claude/agents/` — Agent definitions with file ownership
- `.claude/skills/` — Custom slash commands (/build, /test, /tdd, /phase)
- `.claude/AGENT_COORDINATION.md` — Agent team coordination rules
- `.mcp.json` — MCP servers (empty for Phase 1; Phase 3 adds workout MCP server)
