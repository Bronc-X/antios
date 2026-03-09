# ANTIOS10 Agent Execution Plan

> Status: active
> Updated: 2026-03-07
> Purpose: execution contract for sensor-first memory + agent-first product delivery

---

## 1. Flow Blueprint

### Entry Paths

Primary entry paths:
- passive sensor sync
- Home next-action tap
- proactive reminder
- manual open of Coach

### Main Path

1. `Sensor ingest`
   - HealthKit / Apple Watch data enters structured storage
2. `Body interpretation`
   - system generates sensor-derived memories
3. `Agent initiation`
   - Coach opens with one focused prompt or card
4. `Structured capture`
   - user responds by chip, slider, yes/no, or short free text
5. `Evidence grounding`
   - RAG combines body memory, behavior memory, and science evidence
6. `Action issuance`
   - agent gives one action with measurable follow-up
7. `Commit and review`
   - user marks done, reports result, and closes the loop

### Alternate Paths

- `No wearable data`
  - fall back to recent calibration + inquiry + plan signals
- `No vector retrieval`
  - use lexical fallback and conservative actions
- `No remote AI`
  - keep local soothing mode and preserve action completion capture

---

## 2. Interaction Matrix

### Home -> Coach Handoff

- Trigger: tap next action or evidence card
- Transition: native push or sheet, 220-280ms
- Haptic: `UIImpactFeedbackGenerator(style: .light)`
- Interruptibility: yes
- Error fallback: open Coach with conservative starter prompt

### Daily Check-In Card

- Trigger: proactive agent prompt or Home entry
- Surface: inline thread card
- Controls: 0-10 slider, single-select chips, optional short note
- Feedback: instant state update within 120ms
- Haptic: `selectionChanged` on value snap, `light` on submit
- Reduced motion: opacity only

### Plan Completion Card

- Trigger: agent proposes action or follow-up review
- Surface: inline checklist card
- Controls: done / skipped / too hard
- Feedback: optimistic completion state + follow-up question
- Error fallback: keep local state, retry remote write

### Evidence Card

- Trigger: user asks "why" or agent needs to justify action
- Surface: collapsed summary row with expandable source details
- Feedback: 180-220ms expand
- Haptic: `soft`
- Error fallback: show conservative explanation with explicit uncertainty

---

## 3. Component Behavior Notes

### Coach Thread

- Owns the primary task loop
- Must support mixed content:
  - text bubble
  - structured capture card
  - action card
  - evidence card
  - completion card

### Home

- Primary content is `state -> action -> trust`
- Do not place dense forms or multi-step editing here
- Every major CTA should hand off to Coach with prefilled intent

### Memory System

- `sensor_derived` memories must be rank-boosted
- `behavior_signal` memories should remain short and factual
- `chat_turn` memories should keep reflective user signals
- `assistant_strategy` memories should be selective, not all assistant output

---

## 4. Measurement Plan

### Product KPIs

- daily check-in completion rate
- median time from prompt to submitted check-in
- action completion rate
- follow-up answer rate
- Home -> Coach handoff rate

### RAG / Memory KPIs

- body-memory retrieval hit rate
- empty retrieval rate
- evidence-grounded response rate
- proactive brief usefulness proxy
- vector write success / buffered rate

### Event Contract

Add or preserve instrumentation for:
- `sensor_memory_written`
- `body_memory_retrieved`
- `agent_checkin_started`
- `agent_checkin_submitted`
- `agent_action_committed`
- `agent_followup_answered`
- `coach_handoff_opened`
- `rag_empty_body_memory`

---

## 5. Engineering Execution Threads

### Thread 1: Sensor Memory Foundation

Files:
- `antios10/Core/Networking/SupabaseManager.swift`
- `antios10/Core/Services/Max/MaxMemoryService.swift`
- `antios10/Core/Services/Max/MaxRAGService.swift`

Output:
- memory kind classification
- wearable-derived memory generation
- body-memory-aware ranking

### Thread 2: Agent Router Foundation

Files:
- `antios10/Features/Max/MaxChatView.swift`
- `antios10/Features/Max/MaxChatViewModel.swift`
- later new router files

Output:
- intent-to-card routing
- structured capture primitives

### Thread 3: Workflow Migration

Files:
- `antios10/Features/Calibration/*`
- `antios10/Features/Plans/*`
- `antios10/Features/Dashboard/*`

Output:
- thread-first calibration
- thread-first plan execution
- Home simplification

### Thread 4: Validation

Files:
- `antios10.xcodeproj`
- telemetry probes
- tests to be added

Output:
- build validation
- regression notes
- KPI checklist

---

## 6. Immediate Backlog For Agent

1. Add body-memory and memory-kind support to the existing memory pipeline.
2. Generate body memories during Apple Watch sync.
3. Route `captureUserSignal` into `behavior_signal` instead of generic memory.
4. Reweight RAG memory formatting so body signals surface first.
5. Prepare Coach to host structured action cards in the next implementation pass.
