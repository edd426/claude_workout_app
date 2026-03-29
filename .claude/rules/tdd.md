# Test-Driven Development (Red-Green-Refactor)

## The Cycle

Every feature, bug fix, or behavior change follows this cycle:

### 1. RED — Write a failing test
- Write a test that describes the desired behavior
- Run it. It MUST fail. If it passes, the test isn't testing anything new.
- Confirm it fails for the RIGHT reason (missing method, wrong value — not a compile error or import issue)

### 2. GREEN — Make it pass with minimum code
- Write the simplest implementation that makes the test pass
- Do NOT add extra logic, edge cases, or abstractions yet
- Run the test. It MUST pass.

### 3. REFACTOR — Clean up while staying green
- Improve naming, extract helpers, remove duplication
- Run tests after each change — they must stay green
- This is where design emerges from the code, not before

### Bug Fixes
When fixing a bug: write a failing test that reproduces the bug FIRST, then fix.

## Swift Testing Framework

Use Apple's Swift Testing — NOT XCTest.

```swift
import Testing
@testable import ClaudeLifter

@Suite("WorkoutSet Tests")
struct WorkoutSetTests {
    @Test("Completed set records timestamp")
    func completedSetRecordsTimestamp() {
        // Arrange
        var set = WorkoutSet(order: 1, weight: 60, reps: 8)

        // Act
        set.markCompleted()

        // Assert
        #expect(set.isCompleted == true)
        #expect(set.completedAt != nil)
    }

    @Test("Weight conversion kg to lbs", arguments: [
        (60.0, 132.28),
        (100.0, 220.46),
    ])
    func weightConversion(kg: Double, expectedLbs: Double) {
        let converted = kg.toLbs()
        #expect(abs(converted - expectedLbs) < 0.1)
    }
}
```

### Key Rules
- `@Test("descriptive behavior")` — not `func testSomething()`
- `#expect(condition)` — not `XCTAssertEqual`
- `#require(condition)` — for preconditions that should abort the test
- `@Suite("Group Name")` — to group related tests
- One behavior per test (multiple `#expect` on the same concept is fine)
- Use `arguments:` for parameterized/data-driven tests
- Mark SwiftData tests `@MainActor` (required for `mainContext`)

### Arrange-Act-Assert
Structure every test body as:
1. **Arrange** — set up the system under test and its dependencies
2. **Act** — perform the action being tested
3. **Assert** — verify the outcome with `#expect`

### SwiftData Tests
```swift
func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Exercise.self, Workout.self, WorkoutSet.self,
        configurations: config
    )
}

@Test("Inserting a workout persists it")
@MainActor
func insertWorkout() throws {
    let container = try makeTestContainer()
    let context = container.mainContext
    let workout = Workout(name: "Push Day", startedAt: .now)
    context.insert(workout)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Workout>())
    #expect(fetched.count == 1)
}
```

### Mocking
- Use protocol-based manual mocks (no mocking library needed)
- Mock implements the protocol, stores call counts and arguments for verification
- Place mocks in `ClaudeLifterTests/Helpers/`
