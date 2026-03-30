# Agent Coordination

## File Ownership

Each agent owns specific directories. An agent MUST NOT modify files outside its ownership.
See `CLAUDE.md` for the ownership table.

If an agent needs a change in another agent's files, document it with a `@needs:` tag:

```swift
// @needs: WorkoutRepository.getRecentSets(for exerciseId: UUID, limit: Int) -> [WorkoutSet]
```

The owning agent picks up `@needs:` tags and implements them.

## Dependency Order

```
Phase 2 execution:

  infra (WP-1: Bicep) ──── data-models (WP-3: Models/DTOs/Repos)
       │                        │
       ▼                        ▼
  infra (WP-2: Functions) ─ data-models (WP-4: Sync layer)
       │                        │
       ▼                        ├──────────────────┐
  ┌────┴───────────┐            │                  │
  │                │            ▼                  ▼
  ai-chat (WP-5)  │    ui-viewmodels (WP-6)  ui-viewmodels (WP-7)
  Anthropic proxy  │    Calendar heatmap      Photo capture
  │                │            │                  │
  ▼                ▼            ▼                  ▼
              reviewer (last)
```

1. `infra` and `data-models` start in parallel (Sprint 1-2)
2. `ai-chat`, `ui-viewmodels` run in parallel after data-models completes (Sprint 3)
3. `reviewer` runs last — reviews all committed code

## Commit Convention

Every commit is prefixed with the agent name:

```
[data-models] Add Exercise and ExerciseTag models (6/6 tests passing)
[ui-viewmodels] Add ActiveWorkoutView with set logging (4/4 tests passing)
[ai-chat] Add AnthropicService with streaming support (3/3 tests passing)
[reviewer] Review: Phase 1 data layer — all checks passing
```

Include test status in the commit message.

## Coordination Rules

1. **Protocol-first**: `data-models` agent should commit protocol definitions early, before full implementations, so other agents can start.
2. **No cross-editing**: If you need a change in another agent's file, use `@needs:` — don't edit it yourself.
3. **Test independence**: Each agent's tests should run independently using mocks, not depend on other agents' implementations.
4. **Shared test helpers**: `TestModelContainer.swift` and `TestFixtures.swift` are owned by `data-models` but used by all. Keep them stable.
