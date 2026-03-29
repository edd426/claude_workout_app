---
name: build
description: Build the ClaudeLifter Xcode project and report results.
user-invocable: true
allowed-tools: Bash, Read
---

Build the ClaudeLifter Xcode project.

## Steps

1. Run the build:
   ```bash
   xcodebuild \
     -scheme ClaudeLifter \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     build 2>&1 | tail -30
   ```

2. Report results:
   - If successful: "Build succeeded"
   - If failed: show compiler errors with file:line references
