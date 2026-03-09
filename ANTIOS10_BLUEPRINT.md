# ANTIOS10 Blueprint

> Status: active latest-app blueprint for `codex/antios10`
> Updated: 2026-03-07
> Scope: sensor-first + agent-first iOS rebuild for AntiAnxiety

---

## 1. Product Doctrine

`antios10` is not a shell refresh. It is a product reset around two non-negotiable rules:

1. `Sensor-first memory`
2. `Agent-first product`

This branch should stop treating wearable data as a side signal and stop treating chat as one feature among many.

Primary goals:
- make Apple Watch / HealthKit body signals the highest-value memory input
- turn Max into the main execution surface for calibration, explanation, action, and follow-up
- reduce manual form burden by replacing it with agent-led structured capture
- keep `Home / Coach / Me`, but move capability gravity toward `Coach`
- preserve clinical safety, evidence grounding, and release discipline

Non-goals for this branch:
- full backend rewrite before the new loop is proven
- non-Apple wearable support
- payment launch in v1
- replacing Supabase Auth

---

## 2. Core Architecture Decision

### 2.1 Sensor-First Memory

The most important user memory is not free text. It is body-state evidence derived from:
- HRV
- resting heart rate
- sleep score / sleep recovery
- steps / activity load
- later: respiratory rate, temperature, sleep stages, workout recovery

Rule:
- raw sensor time series stay structured
- only high-value interpretations enter vector memory
- body-state memory outranks chat memory and event logs during grounding

### 2.2 Agent-First Product

The main operating system is the agent thread, not a collection of manual forms.

Rule:
- every critical capability must be invokable from `Coach`
- input should be primarily agent-led cards, chips, sliders, toggles, and confirmations
- standalone screens remain as fallback and overview surfaces, not the primary workflow

---

## 3. Product Shell

### 3.1 Primary Navigation

The main shell remains:

1. `Home`
2. `Coach`
3. `Me`

### 3.2 Capability Gravity

- `Home` becomes the state dashboard and launcher
- `Coach` becomes the primary operating surface
- `Me` keeps permissions, sync, account, language, and release/debug info

### 3.3 Capability Mapping

- `Dashboard` -> `Home` summary + `Coach` handoff
- `Report` -> `Home > Evidence` preview + `Coach` explanation handoff
- `Max` -> `Coach` primary surface
- `Plans` -> `Coach` generated plan + `Home` progress card
- `Calibration` -> agent-led check-in inside `Coach`, page retained as fallback
- `Inquiry` -> agent-led prompts inside `Coach`
- `Science Feed` -> evidence browser, but recommendation framing comes from `Coach`

---

## 4. Flow Blueprint

The anti-anxiety loop becomes:

1. `Observe`
2. `Interpret`
3. `Initiate`
4. `Explain`
5. `Commit`
6. `Review`

### 4.1 Observe

Passive first:
- Apple Watch / HealthKit sync
- local and remote ingestion
- baseline body-state assembly

### 4.2 Interpret

System derives high-value body memories such as:
- low recovery
- elevated physiological arousal
- low movement / low decompression
- post-action improvement patterns

These derived memories are stored for RAG and agent personalization.

### 4.3 Initiate

Max opens the next loop step through:
- proactive prompt
- daily check-in card
- one-tap follow-up
- context-aware reminder

### 4.4 Explain

Max provides:
- concise understanding
- mechanism explanation
- evidence source
- one low-friction next action

### 4.5 Commit

The user completes a micro-action through the thread:
- tap to confirm
- mark done
- select how hard it felt
- pick a follow-up option

### 4.6 Review

The agent closes the loop by asking:
- what changed in body sensation
- what changed in perceived stress / panic
- whether the action helped

---

## 5. Memory Architecture

### 5.1 Memory Layers

The new memory stack is:

1. `raw sensor store`
2. `sensor-derived memory`
3. `behavior loop memory`
4. `chat memory`
5. `assistant strategy memory`

### 5.2 Storage Rule

- `raw sensor store`
  - keep in structured tables such as `user_health_data`
- `sensor-derived memory`
  - write concise body-state summaries into `ai_memory`
  - highest retrieval priority
- `behavior loop memory`
  - calibration completion, habit completion, plan progress, inquiry answers
- `chat memory`
  - reflective user statements and selective assistant turns
- `assistant strategy memory`
  - proactive brief, validated intervention patterns, reusable follow-up scripts

### 5.3 Retrieval Rule

RAG should prefer:

1. body-state memory
2. recent loop behavior memory
3. user reflective memory
4. assistant strategy memory
5. generic knowledge base

`wearable summary` remains useful, but it is not enough. It must be complemented by vectorized body memories.

---

## 6. Agent-First Surface Model

### 6.1 Coach Responsibilities

`Coach` must be able to:
- start daily check-in
- ask structured follow-up questions
- collect plan completion
- request symptom intensity
- explain evidence
- issue the next action

### 6.2 Input Patterns

Prefer these interaction types over manual form pages:
- single-select chips
- intensity slider
- stepper for minutes / repetitions
- yes / no confirmation row
- quick-reply cards
- completion checkmark
- expandable evidence source row

### 6.3 Home Responsibilities

`Home` should answer only:
- what state am I in
- what is the next best action
- why should I trust it
- do I need to open Coach now

Home should not become a second complex workflow surface.

---

## 7. System Architecture

### 7.1 Data Plane

- `HealthKitService`
  - ingests raw Apple Watch / HealthKit data
- `SupabaseManager`
  - persists raw sensor points
  - updates unified traits
  - generates sensor-derived memories
- `MaxMemoryService`
  - stores categorized memories
  - exposes retrieval and fallback
- `MaxRAGService`
  - prioritizes body memory and behavior memory
- later: split into `HealthSyncClient`, `MemoryClient`, `AgentClient`, `EvidenceClient`

### 7.2 Agent Plane

Add an explicit `agent action router` layer:
- map user intent -> action type
- map action type -> thread card / remote write / follow-up question
- own conversation-driven form replacement

Initial route families:
- `check_in`
- `inquiry`
- `plan_commit`
- `plan_review`
- `evidence_explain`
- `sensor_follow_up`

### 7.3 UI Plane

- `Home`
  - loop overview
  - evidence preview
  - next action
  - open Coach
- `Coach`
  - thread
  - structured cards
  - action handoff
  - completion / review loop
- `Me`
  - permissions
  - health sync
  - language
  - account

---

## 8. Execution Phases

### Phase A1: Sensor Memory Foundation

- generate sensor-derived memories during Apple Watch / HealthKit sync
- classify memories by kind
- make body memory visible to RAG

### Phase A2: Retrieval Reweighting

- add memory-kind-aware ranking
- reduce mixed-pool event noise
- preserve lexical fallback for degraded paths

### Phase A3: Agent Action Router

- introduce action routing in Coach
- define thread cards for check-in, completion, evidence, and follow-up

### Phase A4: Agent-Led Calibration and Plans

- move daily calibration to thread-first capture
- move plan commit / progress updates into thread actions
- keep pages as fallback

### Phase A5: Home Simplification

- make Home a launcher and state surface
- reduce workflow duplication outside Coach

### Phase A6: Infra Decomposition and Release

- split `SupabaseManager`
- add telemetry and regression coverage
- recover release readiness

---

## 9. Success Criteria

This direction is successful when:
- Apple Watch / HealthKit derived memory becomes a first-class grounding source
- Max can drive the main anti-anxiety loop without requiring page hopping for every step
- daily check-in completion time drops
- plan follow-through rate increases
- evidence explanation is grounded in body state plus scientific sources
- the app still passes build validation or a concrete blocker is documented

---

## 10. Immediate Agent Work Queue

Immediate code work after this blueprint:
- add categorized memory storage and body-memory priority
- capture sensor-derived memories from wearable sync
- route existing user signals into memory kinds instead of one generic pool
- prepare Coach for agent-led cards and execution actions

Detailed execution steps live in:
- `ANTIOS10_AGENT_EXECUTION_PLAN.md`
