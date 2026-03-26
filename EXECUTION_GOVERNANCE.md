# Antios10 Delivery Governance

## Project Guardrail
- All implementation changes for this delivery happen under `/Users/mac/Desktop/antios10`.
- The active branch for this workspace is `main`.
- Do not switch this workspace to `old10`.
- If work is requested against `old10`, redirect execution to `/Users/mac/Desktop/antios5`.

## Core Delivery Principles

### Principle 1: Sensor-First Memory
- Apple Watch / HealthKit derived body-state memory is the highest-value grounding input.
- Raw sensor data stays structured.
- Only high-value interpretations enter vector memory.

### Principle 2: Agent-First Product
- `Max` is the primary operating surface.
- Critical workflows should be driven through agent-led structured capture before standalone forms.
- Home and dedicated pages should act as overview and fallback surfaces unless explicitly justified.

Current phase tracking lives in:
- `HARNESS_AGENT_DEVELOPMENT_PROCESS.md`

## Dual-Agent Roles

### Agent A: Architecture Planner
Scope:
- Translate product direction into memory contracts, routing rules, and migration phases.
- Define where sensor memory outranks event logs and chat history.
- Maintain blueprint and execution-plan alignment.

Deliverables:
- blueprint and execution-plan updates
- ADR-style decisions for risky tradeoffs
- phase acceptance criteria

### Agent B: Code Engineer
Scope:
- Implement production-grade SwiftUI and service changes.
- Wire sensor-derived memory, RAG ranking, and agent workflow infrastructure.
- Maintain buildability and rollout safety.

Deliverables:
- working code in `antios10`
- validation evidence
- module-level change summaries

## Delivery Threads

### Thread 1: Memory Contract and RAG Alignment
- Output: memory kinds, retrieval priority, sensor-memory integration.
- Priority: highest.

### Thread 2: Sensor Data Plane
- Output: HealthKit ingestion -> structured persistence -> derived body memory -> RAG grounding.
- Dependency: Thread 1 contracts.

### Thread 3: Agent Router and Workflow Migration
- Output: Max-led check-in, evidence, action, and follow-up flows.
- Dependency: Thread 1 and Thread 2.

### Thread 4: Home Simplification and Fallback Surfaces
- Output: Home as state/action launcher, page-level fallback retained where needed.
- Dependency: Thread 3 direction.

### Thread 5: Integration and Release Readiness
- Output: telemetry checks, build validation, regression gates, release recovery.
- Dependency: previous threads.

## Merge Discipline
- Merge sequence should preserve contract-first delivery:
  - Thread 1
  - Thread 2
  - Thread 3
  - Thread 4
  - Thread 5
- No code change should land without matching blueprint / execution-plan alignment.
- Every merge candidate should pass simulator build validation or record a concrete blocker.
