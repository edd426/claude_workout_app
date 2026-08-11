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

Write the full log to a file and grep it. Do NOT pipe `xcodebuild` straight
into `tail` — without `set -o pipefail` that reports `tail`'s exit code, and a
run that returned 65 reads as success.

1. Run the tests, capturing the real exit code:
   ```bash
   set -o pipefail
   LOG=$(mktemp -t claudelifter-test)
   xcodebuild test \
     -scheme ClaudeLifter \
     -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' \
     ${ARGUMENTS:+-only-testing:"ClaudeLifterTests/$ARGUMENTS"} \
     > "$LOG" 2>&1
   echo "EXIT=$?"
   ```

2. Extract results from `$LOG` — **both** frameworks, since they report
   differently and grepping one format hides the other:
   ```bash
   grep -E "Test run with" "$LOG" | tail -2          # Swift Testing totals
   grep -E "^✘" "$LOG"                               # Swift Testing failures
   grep -cE "^Test Case .* passed" "$LOG"            # XCUITest passes
   grep -E "^Test Case .* failed" "$LOG"             # XCUITest failures
   ```

3. Report total run/passed/failed, each failure's name and file:line, and a
   clear PASS or FAIL. **`EXIT=0` is the verdict** — a summary line is not.

## Notes

- The destination must be **iPhone 13 Pro Max**, matching Evan's phone. Do not
  substitute a newer simulator; an iPhone 17 run once produced a false
  `ChatCoachTests` failure. If it is missing, create it (command in CLAUDE.md).
- For the highest-fidelity run, target the phone itself — but it must be
  **unlocked**, or the build is interrupted before it starts.
