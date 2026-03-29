# SwiftData Patterns

## Model Classes

```swift
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \ExerciseTag.exercise)
    var tags: [ExerciseTag]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.tags = []
    }
}
```

### Rules
- `@Model` classes are reference types (must be `class`, not `struct`)
- Use `@Attribute(.unique)` for natural keys (e.g., `id`)
- Use `@Relationship(deleteRule: .cascade)` for parent-child (deleting a Workout deletes its WorkoutExercises)
- Use `@Relationship(deleteRule: .nullify)` for references (deleting an Exercise nullifies references in templates)
- Provide `init` with sensible defaults

## Repository Pattern

Every data access goes through a repository protocol:

```swift
protocol WorkoutRepository {
    func fetchAll() async throws -> [Workout]
    func fetch(id: UUID) async throws -> Workout?
    func save(_ workout: Workout) async throws
    func delete(_ workout: Workout) async throws
}

final class SwiftDataWorkoutRepository: WorkoutRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
    // ...
}
```

### Rules
- Views and ViewModels NEVER access `ModelContext` directly
- ViewModels receive repository protocols via init
- Repository methods are `async throws`
- Use `FetchDescriptor` with `#Predicate` for queries
- Protocol file and implementation file live side-by-side in `Repositories/`

## Testing

- Always use `isStoredInMemoryOnly: true` — fast, isolated, no cleanup
- Create a shared helper in `ClaudeLifterTests/Helpers/TestModelContainer.swift`
- Register ALL model types in the test container
- Mark tests `@MainActor` when using `mainContext`
- Test business logic and query behavior, not SwiftData internals

## Migration
- Use `VersionedSchema` for schema changes after Phase 1 ships
- Not needed during initial development
