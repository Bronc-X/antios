# Antios V2 SwiftData Branch Blueprint

## Branch Strategy

- Recommended branch name: `codex/antios-v2-swiftdata`
- Keep the current `antios10` target intact until V2 reaches beta parity.
- Do not port giant files wholesale. Migrate contracts and focused logic only.
- Treat V2 as a new app shell on top of existing domain assets.

## Why This Branch Exists

Antios is currently heavy because:

- app shell, routing, and root gating are coupled in one flow
- networking and backend compatibility logic are concentrated in one giant manager
- multiple features compete for first-screen priority
- visual direction is rich but not product-tight

This branch is meant to produce a release-ready V2 with:

- a simpler anti-anxiety closed loop
- SwiftData-based local cache
- smaller feature boundaries
- a cleaner path for future reusable iOS starter work

## Product Scope For V2

### Keep For First Release

- auth
- onboarding
- HealthKit authorization + daily signal intake
- home closed loop
- Max chat
- one action surface (breathing / calibration / plan)
- paywall
- profile and lightweight settings

### Defer Or Demote

- science feed as a primary nav item
- digital twin as a primary nav item
- core hub
- heavy settings sprawl
- partially wired live activity flows
- non-essential widgets and experiments

## Information Architecture

Use 3 tabs, not 5:

1. `Home`
2. `Max`
3. `You`

Rules:

- `Home` owns today's state, one explanation, one action, and one follow-up.
- `Max` owns chat, quick actions, and conversational history.
- `You` owns profile, subscription, settings, history, and secondary tools.
- Reports, science feed, and long-form evidence become drill-down destinations from `Home`, not top-level tabs.

## Target And Package Layout

Create one new app target and three local packages.

```text
Packages/
  AntiosDomain/
  AntiosDesignSystem/
  AntiosData/

antiosRelease/
  App/
  Navigation/
  Features/
    Launch/
    Auth/
    Onboarding/
    Home/
    Max/
    Practice/
    Billing/
    Profile/
    History/
  Integrations/
    HealthKit/
    StoreKit/
    Notifications/
  Resources/
```

### Package Responsibilities

#### `AntiosDomain`

Pure domain layer. No UI. No platform framework dependency except Foundation.

- closed-loop contracts
- user/session models
- chat domain models
- plan domain models
- repository protocols
- business rules
- formatting helpers that are not UI-specific

#### `AntiosDesignSystem`

Reusable SwiftUI design system.

- color tokens
- spacing/radius/elevation tokens
- typography scale
- button/card/list row primitives
- skeleton/loading components
- motion rules
- tab bar and sheet chrome

#### `AntiosData`

Data orchestration and persistence.

- API DTOs
- remote clients
- repository implementations
- SwiftData models
- local cache policies
- sync queue
- mapping between remote DTOs and domain models

### App Target Responsibilities

`antiosRelease` should only compose:

- scenes
- feature view models
- navigation
- platform integrations
- dependency injection

It should not contain giant all-purpose managers.

## SwiftData Role In V2

SwiftData is a local cache and local state layer, not the primary cloud truth.

### Store In SwiftData

- cached dashboard snapshot
- cached explanation card
- cached action plan summary
- cached conversation list and recent messages
- onboarding progress
- local user preferences
- pending sync events
- last successful refresh timestamps
- lightweight history used for offline fallback

### Do Not Store In SwiftData As Canonical Truth

- auth source of truth
- subscription entitlement source of truth
- full remote analytics source of truth
- long-term clinical records that are owned by backend workflows

### Special Rule For Health Data

- do not dump raw HealthKit history into a long-lived app-owned replica
- cache only the minimum derived snapshot needed for UX fallback
- keep HealthKit as the device source and remote backend as the server source when sync is required
- do not route personal health data into iCloud / CloudKit

## SwiftData Model Set

Start with a minimal schema:

- `CachedDashboardSnapshot`
- `CachedInsightCard`
- `CachedActionPlan`
- `CachedConversation`
- `CachedMessage`
- `PendingSyncEvent`
- `UserPreference`
- `LocalAppState`
- `RefreshCheckpoint`

Rules:

- every cache entity needs `updatedAt`
- network-driven cache entities need `expiresAt`
- conversation/message cache needs stable remote IDs when available
- pending sync items need retry state and last error summary

## Repository Split

Replace `SupabaseManager` with focused repositories and clients.

### Remote Clients

- `AuthAPIClient`
- `ProfileAPIClient`
- `LoopAPIClient`
- `ChatAPIClient`
- `BillingAPIClient`
- `FeedAPIClient`
- `AppAPIResolver`

### Repositories

- `AuthRepository`
- `HomeRepository`
- `ConversationRepository`
- `PracticeRepository`
- `ProfileRepository`
- `BillingRepository`

### Platform Services

- `HealthKitService`
- `StoreKitEntitlementService`
- `NotificationService`

## Read And Write Flow

### Read Path

1. launch app
2. hydrate from SwiftData immediately
3. render cached shell in under one frame budget
4. refresh remote in background
5. merge remote result into SwiftData
6. update UI from repository output

### Write Path

1. user performs action
2. write optimistic local state
3. append `PendingSyncEvent`
4. attempt remote sync
5. mark success or retry status

This makes the app feel fast even when the network or AI backend is slow.

## Feature Blueprint

### `Launch`

- splash
- session restore
- app state bootstrap
- initial cache hydration

### `Auth`

- sign in
- sign up
- session validation

### `Onboarding`

- first-run flow
- HealthKit permission education
- first baseline capture

### `Home`

- today's status
- one explanation
- one next action
- one follow-up question
- offline cached fallback state

### `Max`

- conversations
- messages
- starter prompts
- quick actions into practice flows

### `Practice`

- breathing
- calibration
- action completion logging

### `Billing`

- StoreKit 2 paywall
- entitlement state
- locked feature gates

### `Profile`

- profile settings
- language
- privacy
- notification preferences

### `History`

- recent sessions
- recent actions
- recent explanations

## Migration Table

### Reuse Logic

- `antios10/Core/HealthKit/HealthKitService.swift`
- `antios10/Core/Services/Max/*` domain logic after dependency cleanup
- `antios10/Models/*`
- selected closed-loop contract types

### Rebuild, Do Not Port As-Is

- `antios10/ContentView.swift`
- `antios10/Features/CoreHub/CoreHubView.swift`
- `antios10/Features/Settings/SettingsView.swift`
- `antios10/Core/Networking/SupabaseManager.swift`

### Port By Slicing

- dashboard logic -> split into `HomeRepository`, `HomeViewModel`, cache mapper
- Max chat logic -> split into `ConversationRepository`, `MessageComposer`, `MaxViewModel`
- profile/settings logic -> split into `ProfileRepository` and small settings screens

## Design Direction

Design system target: calm clinical + warm trust.

Rules:

- fewer full-screen atmospherics
- fewer glass-heavy stacked cards
- stronger typography hierarchy
- one accent color system, not many competing glows
- status, explanation, and action must read in under 5 seconds

Borrow from ShipSwift only at the component pattern level:

- onboarding skeleton
- loading states
- paywall shell
- simple charts if still needed

Do not inherit its generic app aesthetic.

## Release Gates

V2 does not replace V1 until all of these pass:

- auth smoke test
- onboarding smoke test
- HealthKit permission flow
- cached home screen on cold launch
- offline launch with previous snapshot
- Max conversation persistence
- paywall presentation and entitlement refresh
- crash-free first-run pass on device

## Milestones

### M1 - Shell

- create new target
- add package boundaries
- wire DI container
- render empty 3-tab shell

### M2 - Data

- add SwiftData stack
- add repositories
- land cached home and cached conversation flows

### M3 - Core Features

- onboarding
- home loop
- Max
- billing

### M4 - Hardening

- QA
- cleanup
- remove dead V1 dependencies from V2 target
- prepare release checklist

## What Not To Do In This Branch

- do not migrate everything before a runnable shell exists
- do not keep one mega manager "for now"
- do not let five primary tabs survive into V2
- do not use SwiftData as a silent copy of every remote table
- do not couple HealthKit, AI, billing, and settings into one feature module

## First Commit Plan

1. add this blueprint
2. create `antiosRelease` target
3. add package placeholders
4. add empty `Home`, `Max`, `You` tabs
5. add empty SwiftData container bootstrap

Once those exist, start migration by feature slice, not by file copy.
