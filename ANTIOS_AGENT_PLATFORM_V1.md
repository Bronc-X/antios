# ANTIOS Agent Platform V1

> Status: proposed active platform blueprint for `main`
> Updated: 2026-03-23
> Purpose: turn `Max` from an in-app health assistant into an agent-native health runtime for both humans and external agents

---

## 1. Strategic Thesis

`antios10` should not stop at being an agent-first health app.

It should become the first health agent platform designed for:
- humans interacting through native product surfaces
- external agents invoking health capabilities through typed contracts
- large platforms embedding Max as a trusted health execution node

This means `Max` is not just a chat surface.

`Max` becomes:
- the primary human-facing health operating surface
- the canonical health capability runtime
- the interoperability layer for other agents that need health state, recovery actions, evidence explanation, and follow-up loops

The product target is not "better chat."

The product target is:

`the first health agent platform built for both humans and agents`

---

## 2. Product Doctrine

### 2.1 Agent-Native By Default

Every core health capability must be:
- usable by a human in app
- invokable by another agent
- traceable as a structured execution
- resumable if the workflow is long-running

### 2.2 Structured State Before Free Text

Important health state must not live only in natural language.

Primary state must exist as structured objects first:
- body signals
- risk flags
- active plan
- last action outcome
- recovery status
- pending inquiry
- evidence context

Language remains important, but language is not the source of truth.

### 2.3 Capability Over Screen

The unit of platform value is not a page.
The unit of platform value is a trusted health capability.

Examples:
- `check_in`
- `breathing`
- `evidence_explain`
- `inquiry`
- `plan_review`
- later: `panic_deescalation`, `sleep_reset`, `stress_triage`, `handoff_to_clinical`

### 2.4 Platform Adapters Stay Thin

Feishu, Slack, Web, iOS, Siri, service desk, and future assistants should be adapters, not the main system.

Max Core must remain independent of:
- app shell details
- channel-specific message formats
- vendor-specific workflow builders

### 2.5 Bold On Interop, Conservative On Privacy

The system should be aggressive on:
- protocol support
- distribution
- agent discoverability
- long-running workflow orchestration
- platform embedding

The system should remain conservative on:
- health data minimization
- consent
- scoped context sharing
- auditability
- emergency escalation boundaries

---

## 3. What V1 Must Prove

V1 must prove five things:

1. Another agent can discover Max and understand what it can do.
2. Another agent can invoke Max through a typed contract, not only by sending chat text.
3. Max can return structured health outputs, not only prose.
4. Max can run multi-step health workflows and return callbacks or final state.
5. Max can be embedded into a larger platform without rewriting Max Core.

If V1 cannot do these five things, it is still an app with AI, not an agent platform.

---

## 4. Reference Architecture

### 4.1 Layer Model

The target stack is:

1. `Human Surface Layer`
2. `Agent Surface Layer`
3. `Agent Gateway`
4. `Capability Runtime`
5. `Context and Memory Plane`
6. `Evidence and Safety Plane`
7. `Observability and Policy Plane`

### 4.2 Human Surface Layer

Human-facing entry points:
- iOS Coach / Max surface
- Home handoff cards
- App Intents / Siri shortcuts
- notifications and reminders
- widgets and Live Activities

Responsibilities:
- render native interactions
- capture consent
- display progress and results
- keep the loop understandable to the user

Non-responsibilities:
- core routing policy
- external protocol logic
- long-term orchestration ownership

### 4.3 Agent Surface Layer

Agent-facing entry points:
- MCP server
- A2A server
- agent webhook and callback endpoints
- platform adapters for Feishu, Slack, and Web embeds

Responsibilities:
- expose capabilities
- expose scoped context
- accept structured commands
- negotiate sync vs async execution

### 4.4 Agent Gateway

The `Agent Gateway` is the mandatory front door for external agent traffic.

Responsibilities:
- authentication and tenant binding
- capability discovery
- request validation
- idempotency
- trace IDs
- policy enforcement
- callback orchestration
- audit logging

No external agent should call raw app UI pathways directly.

### 4.5 Capability Runtime

This is the canonical execution layer for health actions.

Responsibilities:
- execute capability handlers
- call Max reasoning and RAG
- invoke local or remote model paths
- persist outcomes
- emit structured events

This is where Max stops being "chat" and becomes "runtime."

### 4.6 Context and Memory Plane

This plane provides the minimum trustworthy health context needed for execution.

Core inputs:
- sensor-derived memory
- behavior loop memory
- active plan state
- recent agent outcomes
- profile preferences
- evidence readiness

Core rule:
- external agents get a scoped context snapshot, not the full internal memory graph

### 4.7 Evidence and Safety Plane

Responsibilities:
- evidence retrieval
- mechanism explanation
- conservative fallback behavior
- non-health refusal
- uncertainty disclosure
- crisis and acute-risk boundary handling

### 4.8 Observability and Policy Plane

Responsibilities:
- execution logs
- latency
- success and failure states
- capability usage
- policy decisions
- consent events
- external partner audit trails

---

## 5. Protocol Strategy

### 5.1 MCP For Tools, Resources, and Context

Use MCP when Max needs to expose:
- tools another agent can call
- resources another agent can read
- reusable prompts or capability guidance

MCP should be the default way to expose:
- structured health capabilities
- summarized health context resources
- evidence resources
- plan and follow-up resources

MCP is for `access to capability and context`.

### 5.2 A2A For Peer Agent Collaboration

Use A2A when Max needs to act as a peer agent in a larger workflow.

A2A should cover:
- agent discovery
- capability advertisement
- long-running task handoff
- async result delivery
- collaboration with opaque external agents

A2A is for `agent-to-agent workflow collaboration`.

### 5.3 Platform Adapters For Distribution

Use platform adapters for:
- Feishu bot / API / service desk / workflow trigger
- Slack agent embedding
- Web embeds
- future operating system assistants

Adapters should:
- translate channel events into `AgentCommand`
- translate `AgentExecutionResult` into channel-native output
- preserve trace and audit IDs

Adapters should not:
- implement health logic
- own memory ranking
- duplicate capability rules

---

## 6. Core Contracts

### 6.1 AgentCapability

Every capability exposed to humans or agents should resolve to one canonical definition.

Suggested V1 shape:

```swift
struct AgentCapability: Codable, Hashable {
    let id: String
    let name: String
    let summary: String
    let riskLevel: RiskLevel
    let inputSchemaVersion: String
    let outputSchemaVersion: String
    let supportsSync: Bool
    let supportsAsync: Bool
    let requiresUserVisibleConfirmation: Bool
    let requiresExplicitConsent: Bool
    let producesEvents: [String]
}
```

V1 capability set:
- `check_in`
- `breathing`
- `inquiry`
- `evidence_explain`
- `plan_review`
- `proactive_brief`
- `action_review`

### 6.2 AgentCommand

All external and internal invocations should normalize into one command object.

```swift
struct AgentCommand: Codable {
    let commandID: UUID
    let traceID: UUID
    let actorType: ActorType
    let actorID: String
    let capabilityID: String
    let userID: String?
    let tenantID: String?
    let input: Data
    let contextHintIDs: [String]
    let executionMode: ExecutionMode
    let callbackURL: URL?
    let idempotencyKey: String
    let requestedAt: Date
}
```

Core rule:
- App Intents, notifications, inline action cards, MCP calls, A2A tasks, and platform events should all collapse into `AgentCommand`

### 6.3 AgentContextSnapshot

External agents should not get raw chat history by default.

They should get a scoped snapshot.

```swift
struct AgentContextSnapshot: Codable {
    let snapshotID: UUID
    let userID: String
    let generatedAt: Date
    let bodyState: BodyStateSummary?
    let activePlan: ActivePlanSummary?
    let latestInquiry: InquirySummary?
    let lastActionOutcome: ActionOutcomeSummary?
    let proactiveBrief: ProactiveBriefSummary?
    let evidenceReadiness: EvidenceReadiness
    let riskFlags: [RiskFlag]
    let sharingScope: SharingScope
}
```

### 6.4 AgentExecutionResult

Capability execution must return more than a text string.

```swift
struct AgentExecutionResult: Codable {
    let commandID: UUID
    let traceID: UUID
    let status: ExecutionStatus
    let userVisibleText: String?
    let structuredOutput: Data?
    let nextSuggestedCapabilityIDs: [String]
    let pendingHumanConfirmation: Bool
    let callbackState: CallbackState?
    let emittedEventIDs: [String]
    let completedAt: Date?
}
```

Possible statuses:
- `accepted`
- `running`
- `awaiting_user`
- `completed`
- `rejected`
- `failed`

### 6.5 Capability Event Model

Every execution should emit typed events.

V1 event families:
- `capability_invoked`
- `context_snapshot_generated`
- `evidence_attached`
- `action_started`
- `action_completed`
- `action_too_hard`
- `action_skipped`
- `followup_requested`
- `followup_submitted`
- `external_callback_sent`

---

## 7. Repo Mapping

### 7.1 Existing Strengths

This repo already contains the beginnings of the platform:

- action grammar and routing:
  - `antios10/Core/Services/Max/MaxAgentActionRouter.swift`
- inline action contract:
  - `antios10/Core/Services/Max/MaxPromptBuilder.swift`
- unified Max entry and action handling:
  - `antios10/Features/Max/MaxChatViewModel.swift`
- backend capability boundary:
  - `antios10/Core/Services/ServiceProtocols.swift`
- remote/local Max execution path:
  - `antios10/Core/Networking/SupabaseManager+MaxService.swift`
- OS entry adapters:
  - `antios10/Core/Services/AppShortcuts.swift`
- shell context aggregation:
  - `antios10/Shared/A10ShellSyncCoordinator.swift`

### 7.2 Required Upgrades

#### Upgrade A: Notification Bus -> AgentCommand

Current state:
- notifications and loose `userInfo` payloads drive app actions

Target state:
- all entry paths become `AgentCommand`

Primary insertion points:
- `antios10/Features/Max/MaxChatViewModel.swift`
- `antios10/Core/Services/Max/MaxAgentActionRouter.swift`
- `antios10/Core/Services/AppShortcuts.swift`

#### Upgrade B: Inline Action Card -> Capability Registry

Current state:
- `max-actions` is an app-facing inline DSL

Target state:
- `max-actions` becomes one rendering of canonical capabilities

Primary insertion points:
- `antios10/Core/Services/Max/MaxPromptBuilder.swift`
- `antios10/Models/ChatModels.swift`

#### Upgrade C: App API -> Agent Gateway

Current state:
- remote Max chat is a specialized app API path

Target state:
- app API gains formal agent gateway routes, auth rules, traces, and callback support

Primary insertion points:
- `antios10/Core/Networking/SupabaseManager+AppAPIService.swift`
- `antios10/Core/Networking/SupabaseManager+MaxService.swift`
- remote backend routes to be added outside this repo

#### Upgrade D: Aggregated State -> AgentContextSnapshot

Current state:
- shell hydration builds a rich internal remote context

Target state:
- platform exposes a filtered `AgentContextSnapshot`

Primary insertion points:
- `antios10/Shared/A10ShellSyncCoordinator.swift`
- `antios10/Core/Services/Max/MaxMemoryService.swift`
- `antios10/Core/Services/Max/MaxRAGService.swift`

---

## 8. V1 Platform Surfaces

### 8.1 Human Surfaces

Mandatory:
- Coach / Max thread
- Home next-action handoff
- App Intents
- notification-triggered execution

### 8.2 Agent Surfaces

Mandatory:
- MCP server exposing capabilities and context resources
- A2A server exposing Max as a peer agent
- gateway HTTP endpoints for typed command execution

### 8.3 Distribution Surfaces

Mandatory first-wave targets:
- iOS native
- Feishu adapter
- Web embed

Second-wave targets:
- Slack adapter
- service desk integrations
- enterprise assistant ecosystems

---

## 9. Privacy and Safety Boundary

This system should be bold on interop and strict on health data.

### 9.1 Never Default To Full Transcript Sharing

External agents should not automatically receive:
- raw chat history
- full memory store
- detailed health time series
- sensitive profile attributes not required for execution

### 9.2 Share Minimum Necessary Context

Default export unit:
- summarized state
- current objective
- current action status
- evidence readiness
- explicit risk flags

### 9.3 Consent Requirements

Explicit consent is required before:
- connecting a third-party external agent to personal health context
- allowing write actions that alter the user plan or saved profile
- allowing external callback delivery containing health state

### 9.4 Safety Requirements

The platform must keep:
- non-diagnosis positioning
- acute-risk escalation boundaries
- uncertainty disclosure
- conservative fallback if evidence retrieval fails

---

## 10. V1 Rollout

### Phase 0: Internal Contract Unification

Goal:
- unify internal app entry points before externalizing anything

Deliverables:
- `AgentCommand`
- `AgentCapability`
- `AgentExecutionResult`
- typed command router

Success condition:
- App Intents, notifications, and inline action cards all use the same internal command model

### Phase 1: Capability Registry

Goal:
- turn existing Max actions into canonical platform capabilities

Deliverables:
- capability definitions
- input and output schemas
- risk metadata
- event emission

Success condition:
- each critical Max workflow is invokable without relying on free-text prompt guessing

### Phase 2: Context Snapshot Layer

Goal:
- expose a safe, typed summary of user state for external use

Deliverables:
- `AgentContextSnapshot`
- consent-aware sharing scopes
- snapshot generation path from current shell and memory services

Success condition:
- another agent can make a meaningful call to Max without raw transcript access

### Phase 3: Agent Gateway

Goal:
- make command execution external-ready

Deliverables:
- auth
- tenant binding
- idempotency
- callbacks
- audit logs

Success condition:
- external systems can invoke Max capabilities through a trusted gateway

### Phase 4: MCP and A2A Exposure

Goal:
- make Max discoverable and operable in the agent ecosystem

Deliverables:
- MCP capability server
- MCP resources for context and evidence
- A2A Agent Card and task handling
- async task lifecycle support

Success condition:
- Max is discoverable and callable by other agents as a health node

### Phase 5: Feishu-First Platform Embedding

Goal:
- prove platform distribution through a real enterprise adapter

Deliverables:
- Feishu adapter
- workflow trigger mapping
- service-desk style execution path
- callback and status delivery

Success condition:
- Max runs inside Feishu as an embedded health execution agent without duplicating Max Core

---

## 11. Immediate Build Order For This Repo

### Workstream 1: Define New Shared Types

Create platform-facing domain types for:
- `AgentCommand`
- `AgentCapability`
- `AgentContextSnapshot`
- `AgentExecutionResult`

Likely location:
- `antios10/Models/`
or
- `antios10/Core/Services/AgentPlatform/`

### Workstream 2: Refactor Entry Paths

Refactor:
- App Intents
- ask-Max notification handling
- inline action handling

So they route through one command pipeline.

### Workstream 3: Build Capability Registry

Start with:
- `check_in`
- `breathing`
- `inquiry`
- `evidence_explain`
- `plan_review`

Then bind existing UI and execution handlers to that registry.

### Workstream 4: Add Context Snapshot Builder

Reuse:
- shell remote context
- memory services
- current plan and proactive brief

To build:
- one export-safe snapshot model

### Workstream 5: Prepare Gateway Interface

Define the client-side contract now even if the server implementation lands later.

Need:
- request envelope
- callback envelope
- error model
- execution status model

---

## 12. Non-Goals For V1

Do not do these in V1:
- full marketplace design
- public open discovery for all tenants by default
- non-health general assistant positioning
- diagnosis workflow
- unlimited data sharing with external agents
- vendor-specific logic inside Max Core

---

## 13. Success Criteria

V1 is successful if:
- Max can be invoked by human UI and external agents through the same core command model
- the top health capabilities are callable with typed schemas
- another agent can discover Max and route a task to it
- Max can return structured outputs and async progress
- Feishu-first or equivalent adapter integration works without forking health logic
- privacy boundaries remain strict and auditable

V1 is not successful if:
- the system still depends mainly on free-text chat
- each platform needs a custom Max implementation
- health state remains mostly trapped in UI text
- external interop bypasses consent or auditing

---

## 14. Final Position

The category goal is not:

`health app with AI`

The category goal is:

`health software for humans and agents`

The strategic bet is:

- Feishu proved that agent products become much more valuable when they are embedded into work systems
- emerging agent protocols prove that the next software layer is not just UI integration, but agent interoperability
- health is still mostly app-centric and human-only

This creates an opening for `antios10` to become the first serious health agent platform:
- trusted enough for health context
- structured enough for protocol interoperability
- productized enough for native human use
- modular enough to embed into larger agent ecosystems

That is the correct bar for `Max`.
