# Antios5 Delivery Governance

## Project Guardrail
- All implementation changes must happen under `/Users/mac/Desktop/Antianxiety/antios5`.
- Do not modify files under `/Users/mac/Desktop/Antianxiety/antianxietynew`.

## Dual-Agent Roles

### Agent A: Chief Architecture Planner
Scope:
- Translate latest PRD into target domain model and feature boundaries.
- Define migration strategy from current app to anti-anxiety-first product flow.
- Produce ADR-style decisions for high-risk tradeoffs.

Deliverables:
- Gap matrix (PRD vs current state)
- Module refactor map
- Milestone acceptance checklist

### Agent B: Chief Code Engineer
Scope:
- Implement architecture decisions with production-grade SwiftUI/MVVM code.
- Build data pipeline for onboarding + daily calibration + proactive inquiry + wearable data ingestion.
- Add/adjust tests and runtime guardrails.

Deliverables:
- Working code in antios5
- Integration validation logs
- Change list by module

## Cross-Supervision Protocol
1. Agent A proposes design and risk classification.
2. Agent B challenges technical feasibility and implementation cost.
3. If conflict exists:
- Record both options.
- Resolve by user-value first, complexity second, timeline third.
4. Agent B implementation is blocked until Agent A signs off design constraints.
5. Agent A review is blocked until Agent B provides evidence (build/test/runtime checks).

## Build Threads Plan

### Thread 1: Architecture and PRD Alignment
- Output: final architecture map + API/data contract list.
- Priority: highest (must finish before large implementation starts).

### Thread 2: iOS App Refactor (SwiftUI/MVVM)
- Output: home flow rewrite, onboarding/calibration/proactive inquiry orchestration.
- Dependency: Thread 1 contracts.

### Thread 3: Data and Intelligence Pipeline
- Output: HealthKit ingestion, profile enrichment, RAG evidence assembly, Max response grounding.
- Dependency: Thread 1 entity definitions.

### Thread 4: Integration and Release Readiness
- Output: regression pass, telemetry checks, rollout gates.
- Dependency: Thread 2 + Thread 3 completion.

## Merge Discipline
- Use milestone branches off `antios5` scope.
- Merge order: Thread 1 -> Thread 3 -> Thread 2 -> Thread 4.
- No direct edits in legacy project.
