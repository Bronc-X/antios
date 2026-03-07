# Antios5 Delivery Governance

## Project Guardrail
- All implementation changes for this delivery happen under `/Users/mac/Desktop/antios5`.
- Do not modify other workspaces or legacy copies unless the task explicitly requires it.

## Branch and Worktree Discipline
- `main` is the only long-lived branch for this repository.
- Temporary build/review branches may exist during execution, but they must merge back into `main` and be removed afterward.
- Only one active worktree should point at this repository during product work unless a task explicitly requires an additional worktree.

## Dual-Agent Roles

### Agent A: Chief Architecture Planner
Scope:
- Translate product and research requirements into stable domain boundaries.
- Define migration strategy for closed-loop anti-anxiety flows.
- Record high-risk tradeoffs as ADR-style decisions.

Deliverables:
- Gap matrix (target product vs current app)
- Module refactor map
- Milestone acceptance checklist

### Agent B: Chief Code Engineer
Scope:
- Implement architecture decisions in production-grade SwiftUI/MVVM code.
- Maintain the user data, memory, RAG, and evidence pipeline without hard-coded shortcuts.
- Add build, runtime, and release guardrails.

Deliverables:
- Working code in `antios5`
- Integration validation logs
- Module-level change summary

## Cross-Supervision Protocol
1. Agent A proposes design intent and risk classification.
2. Agent B challenges feasibility, coupling cost, and rollout risk.
3. If conflict exists:
- record both options;
- resolve by user value first, system stability second, implementation cost third.
4. Agent B implementation is blocked until Agent A signs off the constraints.
5. Agent A review is blocked until Agent B provides build/test/runtime evidence.

## Delivery Threads

### Thread 1: Architecture and PRD Alignment
- Output: final architecture map and API/data contract list.
- Priority: highest.

### Thread 2: iOS App Refactor
- Output: home shell, onboarding, calibration, proactive inquiry, and action closure orchestration.
- Dependency: Thread 1 contracts.

### Thread 3: Data and Intelligence Pipeline
- Output: profile enrichment, memory capture, RAG evidence assembly, and Max grounding reliability.
- Dependency: Thread 1 entity definitions.

### Thread 4: Integration and Release Readiness
- Output: regression pass, telemetry checks, simulator validation, and rollout gates.
- Dependency: Thread 2 and Thread 3 completion.

## Merge Discipline
- Merge sequence should preserve contract-first delivery: Thread 1 -> Thread 3 -> Thread 2 -> Thread 4.
- No key documentation may be dropped when code changes land.
- Every merge candidate must pass simulator build validation before entering `main`.
