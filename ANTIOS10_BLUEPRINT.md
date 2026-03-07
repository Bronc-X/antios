# ANTIOS10 Blueprint

> Status: active latest-app blueprint for `codex/antios10`
> Updated: 2026-03-07
> Scope: local-first iOS rebuild for AntiAnxiety with SwiftData foundation

---

## 1. Rebuild Goal

`antios10` is not a cosmetic refresh. It is a controlled product and architecture reset for the first App Store release.

Primary goals:
- make the core anti-anxiety loop understandable in 10 seconds
- reduce compile and change blast radius
- move user-facing state to a local-first SwiftData layer
- keep remote services only where they create clear product leverage
- create a reusable iOS delivery pattern for future B-end and C-end AI products

Non-goals for this branch:
- full backend rewrite
- auth provider migration away from Supabase
- payment launch in v1
- non-Apple wearable support

---

## 2. Governance Alignment

This blueprint implements the four governance files as follows:

- `A`: preserve the anti-anxiety closed loop and release discipline
- `B`: consolidate IA into a smaller shell while keeping required capabilities
- `C`: shift current execution from stabilization-only to rebuild bootstrap
- `D`: keep the branch in NO-GO state until parity, security, signing, and validation are restored

Rule:
- capability scope stays
- shell changes are allowed
- local data architecture changes are allowed
- release gates do not soften

---

## 3. Product Shell

### 3.1 Primary Navigation

The main app shell becomes 3 tabs:

1. `Home`
2. `Coach`
3. `Me`

### 3.2 Capability Mapping

- `Dashboard` capability moves into `Home`
- `Report` capability becomes `Home > Evidence` section and detail route
- `Max` capability becomes `Coach`
- `Plans` capability becomes `Home > Today Plan` plus `Coach` plan handoff
- `Settings` capability becomes `Me`

### 3.3 Entry Flow

`Launch -> Auth -> Clinical Baseline -> Onboarding -> Main Shell`

The existing auth and onboarding gates may remain temporarily while the main shell is rebuilt.

---

## 4. UX Blueprint

### 4.1 Home

Purpose:
- answer three questions immediately:
  - what state am I in
  - what is the next smallest useful action
  - what evidence supports that suggestion

Sections:
- daily focus hero
- 4-step loop status
- today plan card
- evidence preview
- quick actions

### 4.2 Coach

Purpose:
- provide the conversational recovery surface
- turn free text into one next action, not a wall of output

Sections:
- active thread
- quick prompts
- action summary after each exchange
- local draft + local history

### 4.3 Me

Purpose:
- hold settings, permissions, health sync status, language, and release/debug info

Sections:
- health and permissions
- language and preferences
- data and sync status
- account

---

## 5. Design Foundation

This rebuild moves away from high-noise purple glass into a calmer, more clinical-but-human direction.

### 5.1 Color Tokens

- `bgCanvas`: `#F5F1EA`
- `bgElevated`: `#FFFDF8`
- `bgInset`: `#ECE4D7`
- `inkPrimary`: `#1F2328`
- `inkSecondary`: `#56606B`
- `inkTertiary`: `#7B8794`
- `lineSoft`: `#D8CEBF`
- `brandPrimary`: `#2F6E62`
- `brandSecondary`: `#C96F4A`
- `success`: `#2E7D5B`
- `warning`: `#C28A2C`
- `danger`: `#B65454`
- `info`: `#5073B8`

### 5.2 Typography

- `display`: 32 / semibold
- `title1`: 24 / semibold
- `title2`: 20 / semibold
- `body`: 16 / regular
- `bodyStrong`: 16 / semibold
- `caption`: 13 / medium

### 5.3 Spacing

4pt scale only:
- `4, 8, 12, 16, 20, 24, 32, 40`

### 5.4 Radius

- `sm`: 12
- `md`: 18
- `lg`: 24
- `pill`: 999

### 5.5 Motion

- tap feedback: 100ms ease-out + `selectionChanged`
- card expand/collapse: 220ms ease-in-out
- tab switch: native + light haptic only
- page state transition: 280ms max
- reduced motion: remove scale/float, keep opacity only

---

## 6. Component Spec

Core components required in the rebuild shell:

- `ShellScaffold`
  - navigation container
  - background
  - section spacing

- `FocusHeroCard`
  - state headline
  - supporting note
  - next action CTA

- `LoopStepRow`
  - step name
  - status
  - optional blocking reason

- `ActionCard`
  - action title
  - duration or effort
  - completion state

- `CoachBubble`
  - user / assistant variants
  - compact timestamps

- `ComposerBar`
  - text input
  - send
  - quick prompt insertion

- `SettingsRow`
  - label
  - subtitle
  - accessory

All new components must bind to tokens, never raw visual literals beyond the token table.

---

## 7. Data Architecture

### 7.1 Local-First Rule

SwiftData becomes the primary UI data layer.

SwiftData owns:
- loop snapshot
- local plan state
- coach thread and coach messages
- local preferences
- local drafts / cache

Remote services own:
- auth and session
- server truth for cross-device records
- AI orchestration
- heavy analytics / recommendation generation

### 7.2 Initial SwiftData Models

- `A10LoopSnapshot`
- `A10ActionPlan`
- `A10CoachSession`
- `A10CoachMessage`
- `A10PreferenceRecord`

### 7.3 Sync Strategy

Phase 1:
- local-only creation and mutation
- remote sync boundary defined but minimal

Phase 2:
- session-aware background sync from SwiftData to Supabase/App API
- conflict strategy: local optimistic write, server reconciliation on fetch

Phase 3:
- durable migration from legacy view models to feature-specific clients

---

## 8. Remote Architecture

Do not push health and mental-health domain data into iCloud persistence.

Recommended remote split:
- keep `Supabase Auth`
- keep Postgres/Supabase as canonical synced store
- keep App API for orchestrated AI workflows
- progressively replace the monolithic `SupabaseManager` with feature clients:
  - `AuthClient`
  - `ProfileClient`
  - `LoopClient`
  - `CoachClient`
  - `HealthSyncClient`

---

## 9. What To Borrow From ShipSwift

Directly reusable later:
- `SWPaywallView` and `SWStoreManager` for a future subscription phase
- lightweight onboarding / settings / loading component patterns
- repository organization rules and AI-readable component conventions

Borrow ideas only:
- `SWRootTabView`
- `SWChat`
- `SWOnboardingView`

Do not adopt:
- `SWAuth`
- `SWTikTokTracking`
- ShipSwift backend assumptions

---

## 10. Execution Plan

### Phase R1: Bootstrap

- write blueprint and governance updates
- create `codex/antios10`
- replace legacy 5-tab main shell with 3-tab rebuild shell
- add SwiftData container and initial models
- seed local demo/runtime data

### Phase R2: Home Loop

- rebuild Dashboard/Report/Plans capability into `Home`
- add loop progression state
- add evidence preview and next-action contract

### Phase R3: Coach

- rebuild Max shell into `Coach`
- local-first thread model
- remote bridge adapter for later sync

### Phase R4: Me

- rebuild Settings into `Me`
- add health permissions summary
- add language/data/sync/account sections

### Phase R5: Infra Decomposition

- split `SupabaseManager` into feature clients
- shrink compile hotspots
- isolate remote DTOs from view state

### Phase R6: Release Recovery

- secrets rotation
- signing recovery
- simulator/test gate repair
- device validation

---

## 11. File-Level Kickoff

Immediate code changes in this kickoff:
- update `antios5App.swift` to host SwiftData
- replace `ContentView.swift` main shell with `Home / Coach / Me`
- keep existing auth/onboarding gates for now
- seed a local SwiftData domain so the rebuild is runnable on day one

Deferred:
- full feature extraction into separate folders/files
- full sync bridge
- legacy feature deletion

---

## 12. Success Criteria For This Kickoff

This kickoff is successful when:
- blueprint is written
- governance files are aligned
- branch exists
- app boots into the new rebuild shell after gates
- new shell reads and writes SwiftData
- project still reaches build validation or a concrete blocker is identified
