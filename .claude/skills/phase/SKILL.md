---
name: phase
description: Show current development phase progress and what's next.
user-invocable: true
allowed-tools: Read, Grep
---

Show the current phase status for ClaudeLifter.

## Steps

1. Read `CLAUDE.md` and find the "Current Phase" section
2. Count checked `- [x]` vs unchecked `- [ ]` items
3. Display:
   - Current phase name
   - Progress: `[=========>          ] 5/14 items (36%)`
   - Completed items (list)
   - Next items to work on (first 3 unchecked)
4. Read `SPEC.md` §11 for details on current and upcoming phases
5. If all items in current phase are checked, announce readiness for the next phase
