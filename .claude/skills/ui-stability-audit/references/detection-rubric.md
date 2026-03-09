# Detection Rubric

## Confidence Levels

- High confidence:
  - simulator build succeeded
  - target flow launched
  - light and dark screenshots captured
  - post-fix screenshots reviewed
  - static findings reviewed for touched files
- Medium confidence:
  - build succeeded
  - only one theme or one flow was captured
  - static findings reviewed
- Low confidence:
  - only code inspection or only static scanning was completed

Do not describe a result as complete when it only meets low confidence.

## Screenshot Checklist

- Is the main container visually centered?
- Do repeated cards, buttons, and pills share the same width rhythm?
- Does any text disappear into the background or look disabled by mistake?
- Does any CTA lose contrast in light mode?
- Does dark mode still look intentional after the fix?
- Does launch or splash state behave differently from the steady-state screen?

## Simulator Command Templates

Determine the current branch:

```bash
git branch --show-current
```

Find bundle identifier and app path:

```bash
xcodebuild -scheme <scheme> -project <project>.xcodeproj -showBuildSettings | rg "PRODUCT_BUNDLE_IDENTIFIER|TARGET_BUILD_DIR|FULL_PRODUCT_NAME"
```

Boot and wait for a concrete simulator:

```bash
xcrun simctl boot <udid> || true
open -a Simulator --args -CurrentDeviceUDID <udid>
xcrun simctl bootstatus <udid> -b
```

Build, install, launch, and capture:

```bash
xcodebuild -quiet -scheme <scheme> -project <project>.xcodeproj -destination 'id=<udid>' build
xcrun simctl install <udid> <path-to-app>

xcrun simctl ui <udid> appearance light
xcrun simctl launch --terminate-running-process <udid> <bundle-id>
xcrun simctl io <udid> screenshot /tmp/ui-light.png

xcrun simctl ui <udid> appearance dark
xcrun simctl launch --terminate-running-process <udid> <bundle-id>
xcrun simctl io <udid> screenshot /tmp/ui-dark.png
```

Run the static scan:

```bash
python3 scripts/scan_swiftui_ui_risks.py <repo-root>
```

Exit code guidance:

- `0`: no heuristic findings
- `1`: findings present
- `2`: execution error

## Claude /loop Notes

Claude Code's built-in `/loop` is session-scoped. It can re-run a prompt or another skill invocation on an interval while the session remains open.

Good examples:

```text
/loop 15m /ui-stability-audit dashboard centering and light-mode contrast
/loop 30m check whether the latest simulator screenshots still show centered cards
```

Important limits:

- if the Claude session exits, scheduled tasks disappear
- recurring tasks expire after 3 days
- tasks fire only when Claude is idle between turns

If you need durable unattended scheduling, use Claude Desktop scheduled tasks or CI instead of relying on a live CLI session.
