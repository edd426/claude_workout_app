---
name: test
description: Run Swift tests for the ClaudeLifter project and display results.
user-invocable: true
allowed-tools: Bash, Read
argument-hint: "[test-filter]"
---

Run tests for the ClaudeLifter Xcode project.

If `$ARGUMENTS` is provided, use it to filter which tests to run (e.g., "ModelTests", "WorkoutSetTests").

## Steps

1. If `$ARGUMENTS` is provided, run only matching tests:
   ```bash
   xcodebuild test \
     -scheme ClaudeLifter \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     -only-testing:"ClaudeLifterTests/$ARGUMENTS" \
     2>&1 | tail -50
   ```

2. If no arguments, run all tests:
   ```bash
   xcodebuild test \
     -scheme ClaudeLifter \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     2>&1 | tail -50
   ```

3. Parse the output and report:
   - Total tests run, passed, failed, skipped
   - For failures: show the test name, file:line, and assertion message
   - End with a clear PASS or FAIL summary
