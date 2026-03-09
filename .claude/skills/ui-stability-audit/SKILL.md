---
name: ui-stability-audit
description: Inspect, fix, and verify SwiftUI and UIKit UI stability issues such as off-center alignment, safe-area drift, unreadable text, and light/dark regressions. Use when the user asks to inspect UI in the simulator, compare screenshots, fix alignment or contrast bugs, or build a repeatable repair loop that can be scheduled with /loop.
argument-hint: [goal or flow]
---

# UI Stability Audit

Run a deterministic inspect -> classify -> act -> verify loop. The default meaning of `/loop` in this workspace is to continue repairing until the current scoped bug list is cleared or a real blocker prevents more progress.

## Invocation Contract

At the start of each run, normalize the request into:

- Objective
- Target flow or screen
- Success criteria
- Bug inventory
- Evidence artifacts to collect

If the request was invoked by Claude's built-in `/loop`, continue from the current repo and simulator state instead of restarting blindly. Re-read the latest evidence first and keep the loop running until there are no remaining known actionable bugs in scope.

## Minimum Evidence Before Claiming Success

Do not say a flow is fixed unless you have all applicable evidence:

- simulator build succeeded, or you clearly reported the build/toolchain blocker
- static findings from `scripts/scan_swiftui_ui_risks.py` reviewed for the touched flow
- screenshots captured for the relevant light and dark states, or a documented reason one state could not be captured
- one post-fix verification pass on the same flow

If only code inspection or only static scanning was completed, call the result heuristic, not verified.

## Pass Structure

For each pass:

1. Inspect
   - read the affected code paths
   - run the static scanner
   - build and launch on a concrete simulator device when runtime verification matters
   - capture screenshots or other artifacts
2. Classify
   - name the root cause category: unstable width basis, safe-area drift, hardcoded contrast, shared component token issue, clipping, or toolchain blocker
3. Act
   - fix the root cause in shared layout helpers, semantic tokens, or reusable components before patching individual screens
   - add or update targeted regression tests when introducing reusable layout or color logic
4. Verify
   - rebuild, relaunch, and re-capture
   - compare before and after artifacts

After verification, refresh the bug inventory and immediately start the next pass if any known actionable bug remains.

## Stop Rules

Stop early and report when any of these becomes true:

- the scoped bug inventory is empty and the final verification evidence is in hand
- a blocker persists and prevents meaningful forward progress
- the user interrupts or changes scope
- more work would require an unavailable permission, service, or external dependency

Do not stop merely because one pass was successful. Keep looping until the scoped bug list is actually clear.

## Priority Order

- Fix hardcoded `.white` and `.black` foreground usage before chasing isolated contrast complaints.
- Fix unstable width math based on `safeWidth`, `UIScreen.main.bounds.width`, or raw `GeometryReader` width before per-screen alignment hacks.
- Fix shared buttons, pills, launch surfaces, and cards before patching repeated call sites.

## Runtime Procedure

- Use `python3 scripts/scan_swiftui_ui_risks.py <repo-root>` for heuristic findings.
- Read `references/detection-rubric.md` when you need the screenshot checklist, simulator commands, or Claude `/loop` scheduling guidance.
- Build against a simulator UDID, not just a device name.
- When a task reaches a stable stop point on macOS and `say` is available, run `say "master job done"` once.

## Reporting Format

Always separate:

- verified fixes
- remaining risks
- infrastructure blockers
- next action, if another `/loop` run should continue

During `/loop`, defer the full close-out until the loop is finished. Use short progress updates while working, then give one consolidated final report when the scoped bug list is clear or blocked.

## Scheduling With Claude /loop

Claude Code's built-in `/loop` can re-run this skill on a cadence. Example:

`/loop 15m /ui-stability-audit dashboard centering and light-mode contrast`

When scheduled this way, each invocation should:

- check the current repo state before editing
- avoid repeating the same failed fix without new evidence
- state whether the loop should keep running or be cancelled
