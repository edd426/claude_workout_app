---
name: build
description: Build the ClaudeLifter Xcode project and report results.
user-invocable: true
allowed-tools: Bash, Read
---

Build the ClaudeLifter Xcode project.

## Steps

1. Run the build, capturing the real exit code rather than piping into `tail`
   (without `set -o pipefail` that reports `tail`'s status, not xcodebuild's):
   ```bash
   set -o pipefail
   LOG=$(mktemp -t claudelifter-build)
   xcodebuild \
     -scheme ClaudeLifter \
     -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max' \
     build > "$LOG" 2>&1
   echo "EXIT=$?"
   grep -E "error: " "$LOG" | head -20
   ```

2. Report results:
   - If successful: "Build succeeded"
   - If failed: show compiler errors with file:line references

## Notes

The destination must be **iPhone 13 Pro Max**, matching Evan's phone — don't
substitute whatever simulator ships newest. If it's missing, create it (command
in CLAUDE.md). To build for the phone itself, see the install recipe in
CONTINUATION.md; the phone must be unlocked.
