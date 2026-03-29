# Swift Code Style

## Naming
- Types: `PascalCase` (structs, classes, enums, protocols)
- Properties, methods, variables: `camelCase`
- Enum cases: `camelCase`
- Protocols for capabilities: `-able`/`-ible` suffix (e.g., `Searchable`)
- Protocols for contracts: descriptive noun (e.g., `WorkoutRepository`)
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)

## ViewModels
- Use `@Observable` macro — NOT `ObservableObject`/`@Published`
- Mark `@MainActor`
- Accept all dependencies via `init` (protocol types, not concrete)
- Keep state logic in ViewModel, keep Views declarative

## Views
- View `body` should be < 30 lines; extract subviews as separate structs
- Use `@Environment` for ModelContainer/ModelContext injection
- Prefer `.task { }` over `.onAppear` for async work
- Dark mode default — test all views in both modes

## Safety
- No force unwraps (`!`) in production code. Use `guard let`, `if let`, or `??`.
- Force unwraps are acceptable in tests with clear context.
- Prefer `guard` for early returns over nested `if let`.
- Use typed throws where the error type is known.

## Concurrency
- `@MainActor` on ViewModels and anything touching UI state
- `async/await` for service methods
- Use `Task { }` in ViewModels for kicking off async work
- Avoid `DispatchQueue` — use structured concurrency

## Access Control
- Default `internal` (omit the keyword)
- `private` for implementation details not needed outside the type
- `public` only if building a module boundary (unlikely for this app)
- Never use `open`

## General
- Trailing closure syntax for the last closure parameter
- Prefer `let` over `var` unless mutation is needed
- Use `[weak self]` in closures only when actually needed (not in `Task { }` — it captures `self` strongly but that's fine for ViewModels)
