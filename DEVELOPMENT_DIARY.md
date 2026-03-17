# Development Diary

## 2026-03-17
- Scope: Continued the `Max` chat refactor on `codex/antios10`, focused on making assistant replies less template-driven and letting replies carry inline action cards that keep users inside the conversation.
- Completed: Relaxed the Max prompt contract so responses are adaptive instead of forced into a fixed response template, while still preserving safety and actionability.
- Completed: Added `MaxInlineActionCard` support and wired the current in-chat actions end to end, including `check-in`, `breathing`, `inquiry`, `evidence`, `plan review`, `continue with Max`, and action outcome marking (`completed`, `too hard`, `skipped`).
- Completed: Rendered assistant-side inline cards in the chat bubble UI and routed taps back into existing Max execution flows so the user can trigger support flows directly from the message.
- Completed: Sanitized `max-actions` card payloads out of inference history so UI protocol blocks are not fed back into later remote or local Max generations.
- Completed: Updated local fallback reply behavior to avoid rigid canned formatting.
- Verification: `xcodebuild -project antios10.xcodeproj -scheme antios10 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:antios10Tests test` succeeded.
- Tomorrow priorities:
1. Expand the action-card system from the current fixed action set into richer product-linked cards, especially cards that can open or complete existing app flows without extra free-text turns.
2. Audit where Max should show a card versus plain text, and add explicit card gating rules so cards appear only when they reduce friction rather than on every answer.
3. Review the current `agentSurface` derivation and tighten stage detection, because card relevance now depends on calibration / inquiry / action / evidence state being correct.
4. Add UI and integration coverage for inline card execution paths, not just parser tests, so regressions in tap handling are caught before shipping.
5. Decide whether plan options and inline action cards should converge into a single message interaction model, since they currently coexist as separate assistant-side protocols.

## 2026-02-07
- Root cause: `WearableConnectViewModel()` is `@MainActor` and was instantiated in a nonisolated context in `CoreHubView` modules; `MaxPlanQuestionGenerator.swift` was missing from Xcode target membership.
- Fix: Marked `CoreHubView` as `@MainActor` and added `MaxPlanQuestionGenerator.swift` to the Xcode project file references and build phases.
- Result: `xcodebuild` (iostest) succeeded.
- Root cause: `InsightBox` gained a required `language` parameter, but `ArticleReaderView` still called it without the argument.
- Fix: Injected `AppSettings` into `ArticleReaderView`, derived `language`, and passed it to both `InsightBox` usages.
- Result: `xcodebuild` (iostest) succeeded.
- Root cause: Simulator networking hit SSL/TLS handshake failures and App API health checks timed out, compounded by strict single-source App API selection and `www` canonicalization.
- Fix: Added a debug-only `NetworkSession` with optional insecure TLS on simulator, increased App API health timeout, removed forced `www` -> bare domain rewrite, and allowed fallback App API selection when the fixed base is unreachable.
- Result: `xcodebuild` (iostest) succeeded.
- Root cause: Per-screen center tweaks were ineffective because global container bias (`CustomTabBar` hardcoded `offset(x: -24)`) and inconsistent header centering structure caused perceived right drift.
- Fix: Removed global horizontal bias in `ContentView`, switched key headers to symmetric side-slot centering (`ScienceFeed`, `DigitalTwin`, `Max`), centered loading blocks structurally, and increased `ScreenMetrics.centerAxisOffset` to `-8` for regular-width devices.
- Result: `xcodebuild` (iostest) succeeded.
