# Anti-Anxiety Architecture Map (antios10)

## Scope Guardrail
- Workspace: `/Users/mac/Desktop/antios10`
- Branch: `main`
- Legacy line lives in `/Users/mac/Desktop/antios5` on `old10`

## Product Loop
1. Sensor observe
2. Body-state interpret
3. Agent initiate
4. Evidence explain
5. Action commit
6. Follow-up review

## System Threads

### Thread A: Memory Contract
- Goal: define memory kinds and retrieval priority.
- Core rule:
  - sensor-derived memory > behavior memory > chat memory > assistant strategy > generic knowledge
- Main files:
  - `antios10/Core/Services/Max/MaxMemoryService.swift`
  - `antios10/Core/Services/Max/MaxRAGService.swift`

### Thread B: Sensor Data Plane
- Goal: HealthKit -> structured persistence -> derived body memory -> RAG context.
- Main files:
  - `antios10/Core/HealthKit/HealthKitService.swift`
  - `antios10/Core/Networking/SupabaseManager.swift`

### Thread C: Agent Surface
- Goal: make Coach the primary workflow surface.
- Main files:
  - `antios10/Features/Max/MaxChatView.swift`
  - `antios10/Features/Max/MaxChatViewModel.swift`
  - later agent router files

### Thread D: Home and Fallback Surfaces
- Goal: keep Home as state/action launcher, not a parallel workflow engine.
- Main files:
  - `antios10/Features/Dashboard/DashboardView.swift`
  - `antios10/Features/Dashboard/DashboardViewModel.swift`

## Data Contracts

### Body Memory Contract
- Input:
  - HRV
  - resting heart rate
  - sleep score
  - steps
- Output:
  - concise derived body-state memories for retrieval

### Agent Action Contract
- Route families:
  - `check_in`
  - `inquiry`
  - `evidence_explain`
  - `plan_commit`
  - `plan_review`
  - `sensor_follow_up`

### Explanation Contract
- Required output:
  - understanding
  - mechanism
  - evidence source
  - one action
  - one follow-up question

## Risk Classification
- R1 Low: additive memory-kind support
- R2 Medium: Home / Coach handoff and thread-card introduction
- R3 High: sensor-memory weighting and workflow migration across existing modules

## Chosen Rollout
- Option A: continue page-first UX and append more AI.
- Option B: move to sensor-first memory and agent-first workflow.
- Chosen: Option B.
- Reason:
  - user value first
  - lower manual burden
  - better personalization quality
  - clearer anti-anxiety loop
