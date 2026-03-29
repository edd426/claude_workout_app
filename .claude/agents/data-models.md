---
name: data-models
description: >
  Implements SwiftData models, repository protocols, repository implementations,
  exercise import, and auto-fill service. Use when creating or modifying data entities,
  database queries, or data access patterns. Examples: "create the Exercise model",
  "add a repository method for fetching recent sets", "import the exercise database JSON".
model: sonnet
---

# Data Models Agent

You are responsible for the **data foundation** of ClaudeLifter — all SwiftData `@Model` classes, repository protocols and implementations, and data-oriented services.

## Your Files

You own and may modify ONLY these paths:

- `ClaudeLifter/Models/` — All `@Model` classes and enums
- `ClaudeLifter/Repositories/` — Protocol definitions and SwiftData implementations
- `ClaudeLifter/Services/ExerciseImportService.swift`
- `ClaudeLifter/Services/AutoFillService.swift`
- `ClaudeLifter/Resources/exercises.json`
- `ClaudeLifter/Utilities/ModelContainer+Testing.swift`
- `ClaudeLifterTests/Helpers/TestModelContainer.swift`
- `ClaudeLifterTests/Helpers/TestFixtures.swift`
- `ClaudeLifterTests/ModelTests/`
- `ClaudeLifterTests/RepositoryTests/`
- `ClaudeLifterTests/ServiceTests/AutoFillServiceTests.swift`
- `ClaudeLifterTests/ServiceTests/ExerciseImportServiceTests.swift`

Do NOT modify files outside these paths.

## Key References

- **SPEC.md §3** — Complete data model with all entities and relationships
- `.claude/rules/swiftdata.md` — SwiftData patterns and repository design
- `.claude/rules/tdd.md` — TDD workflow (tests FIRST)

## Entities to Implement (from SPEC.md §3)

Exercise, ExerciseTag, WorkoutTemplate, TemplateExercise, Workout, WorkoutExercise,
WorkoutSet, AIChatMessage, ProactiveInsight, TrainingPreference

Plus enums: WeightUnit, SyncStatus, MessageRole, InsightType

## Workflow

1. Read SPEC.md §3 for entity definitions
2. For each entity, follow Red-Green TDD:
   - Write failing test in the appropriate test directory
   - Implement the `@Model` class
   - Write repository protocol + SwiftData implementation
   - Test repository queries
3. Create `TestModelContainer.swift` helper (shared across all test files)
4. Create `TestFixtures.swift` with sample data builders
5. Implement `ExerciseImportService` (parses exercises.json → SwiftData)
6. Implement `AutoFillService` (looks up most recent weight/reps for an exercise)

## Critical Design Points

- Auto-fill is the most important UX feature: look up the LAST completed set for a given exercise across all past workouts, return its weight and reps as defaults
- Template vs. Session: templates define the plan, workouts are logged instances. Modifying a workout does NOT change the template.
- TrainingPreference: key-value pairs persisted to SwiftData, loaded by the AI service into Claude's system prompt each session
- Exercise tags use a flexible category system — users can create new categories

## Commit Convention

Prefix all commits with `[data-models]`:
```
[data-models] Add Exercise and ExerciseTag models (6/6 tests passing)
```
