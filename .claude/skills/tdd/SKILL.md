---
name: tdd
description: Start a Red-Green-Refactor TDD cycle for a feature or behavior.
user-invocable: true
argument-hint: "<feature description>"
---

Guide a Red-Green-Refactor TDD cycle for: **$ARGUMENTS**

Follow `.claude/rules/tdd.md` strictly.

## Workflow

### Phase 1: RED
1. Identify the behavior to test from the feature description
2. Determine the correct test file location (ModelTests/, ViewModelTests/, ServiceTests/, RepositoryTests/)
3. Write a failing test using Swift Testing framework (`@Test`, `#expect`)
4. Run `/test` to confirm it fails
5. Verify it fails for the RIGHT reason (not a compile error)

### Phase 2: GREEN
1. Write the minimum implementation to make the test pass
2. Run `/test` to confirm it passes
3. Do NOT add extra logic or edge cases yet

### Phase 3: REFACTOR
1. Review the implementation for clarity and design
2. Extract helpers, improve names, reduce duplication — if warranted
3. Run `/test` after each refactor step to stay green

### Next
Ask: "Do you want to add another test for this feature, or move on?"

If more tests, repeat the cycle. Each test should cover a different behavior or edge case.
