# PRD vs Antios5 Baseline Gap Analysis

## Scope
- Baseline app: `/Users/mac/Desktop/Antianxiety/antios5` (copied from `antianxietynew`)
- Goal: align to latest anti-anxiety-first PRD
- Note: legacy project `/Users/mac/Desktop/Antianxiety/antianxietynew` remains untouched

## Rating Rubric
- Gap: `G0` aligned, `G1` minor, `G2` medium, `G3` major
- Change Size: `S` small, `M` medium, `L` large, `XL` very large
- Coupling Impact (hook-equivalent in SwiftUI/MVVM): `Low`, `Med`, `High`

## Full Comparison Table

| # | PRD Capability (latest route) | Current antios5 baseline (from antianxietynew) | Gap | Change Size | Coupling Impact | Main touched files |
|---|---|---|---|---|---|---|
| 1 | Product narrative: anti-anxiety-first | Home is multi-module health platform style (core hub, quick actions, report-like cards) | G3 | L | High | `antios5/Features/Dashboard/DashboardView.swift`, `antios5/ContentView.swift` |
| 2 | Home should be strict 4-step loop (Max问询→校准→科学解释→行动建议) | Home currently includes many parallel blocks (quick actions, metric grid, insights, logs, hub entry) | G3 | L | High | `antios5/Features/Dashboard/DashboardView.swift`, `antios5/Features/Dashboard/DashboardViewModel.swift` |
| 3 | Max主动问询 should be core orchestrator | Exists, but trigger is mostly page load/refresh pull; not yet full lifecycle orchestrator | G2 | M | High | `antios5/Features/Dashboard/DashboardViewModel.swift`, `antios5/Core/Networking/SupabaseManager.swift` |
| 4 | Registration deep profiling for anxiety understanding | Clinical onboarding exists (GAD-7/PHQ-9/ISI + profile write) | G1 | M | Med | `antios5/Features/Onboarding/ClinicalOnboardingView.swift`, `antios5/Core/Networking/SupabaseManager.swift` |
| 5 | Onboarding data chain consistency | iOS onboarding calls endpoints (`progress/save-step/skip/reset`) not found in current web API tree | G2 | M | Med | `antios5/Features/Onboarding/OnboardingViewModel.swift`, `/Users/mac/Desktop/Antianxiety/app/api/onboarding/recommend-goals/route.ts` |
| 6 | Daily calibration centered on anti-anxiety explanation inputs | Daily calibration exists and is rich, but still broad wellness oriented | G2 | M | High | `antios5/Features/Calibration/CalibrationViewModel.swift`, `antios5/Features/Calibration/CalibrationView.swift` |
| 7 | Wearable data (Apple Watch/HealthKit) must feed user model | HealthKit read + UI sync exists, but backend persistence/model integration is weak | G3 | L | High | `antios5/Core/HealthKit/HealthKitService.swift`, `antios5/Features/Report/ReportViewModels.swift`, `antios5/Core/Networking/SupabaseManager.swift` |
| 8 | Unified profile enrichment to vectorizable high-value dataset | Partial: profile + wellness + logs + memories exist; no clearly unified anti-anxiety feature pipeline | G2 | L | High | `antios5/Core/Networking/SupabaseManager.swift`, `antios5/Core/Services/Max/MaxMemoryService.swift` |
| 9 | RAG for scientific anti-anxiety grounding (paper/consensus/source) | Strong base exists: KB matching + scientific search + rerank | G1 | M | Med | `antios5/Core/Services/Max/MaxRAGService.swift`, `antios5/Core/Services/ScientificSearchService.swift`, `antios5/Core/Services/KnowledgeBaseService.swift` |
| 10 | Home-level “科学解释卡” with evidence transparency | Science exists but mainly separate module/feed; home card is not a strong evidence-explanation unit | G2 | M | Med | `antios5/Features/Dashboard/DashboardView.swift`, `antios5/Features/ScienceFeed/ScienceFeedView.swift` |
| 11 | Chat should provide structured scientific soothing, not generic comfort | Max has advanced context path, but response UX rules need stricter anti-anxiety reasoning format | G2 | M | High | `antios5/Features/Max/MaxChatViewModel.swift`, `antios5/Core/Networking/SupabaseManager.swift` |
| 12 | Action loop closure after explanation (micro-plan/task follow-up) | Plans module exists but linkage from inquiry/calibration to plan closure is not strict by default | G2 | M | High | `antios5/Features/Plans/PlansViewModel.swift`, `antios5/Features/Max/MaxChatViewModel.swift` |
| 13 | Data contracts and backend modularity for new route | Heavy concentration in one large network manager (4216 LOC), risk for wide ripple | G3 | XL | High | `antios5/Core/Networking/SupabaseManager.swift` |
| 14 | Notification/trigger strategy for proactive loop | Some NotificationCenter events exist, but anti-anxiety cadence engine is not explicit | G2 | M | Med | `antios5/ContentView.swift`, `antios5/Features/Settings/SettingsView.swift` |
| 15 | Metrics and acceptance telemetry around “anti-anxiety effectiveness” | Existing score/report metrics focus on overall health/understanding; anti-anxiety KPI not isolated | G2 | M | Med | `antios5/Features/Report/ReportView.swift`, `antios5/Features/Dashboard/DashboardViewModel.swift` |
| 16 | End-to-end test coverage for new closed loop | Current tests are limited for this iOS route and loop-level regression checks are missing | G2 | M | Med | `antios5Tests` (to be expanded), onboarding/calibration/max modules |

## Direct Answer to Your Questions

### Is the gap big?
- Yes, at strategy level it is **large** (`G3` on product narrative, home IA, wearable ingestion-to-model, backend modularity).
- At capability level, this is **not a rewrite from zero** because core building blocks already exist.

### Is modification large?
- Yes, but it is **refactor + re-orchestration**, not greenfield.
- Expected overall size: `L~XL` depending on how deep backend contracts are changed.

### Are many hooked modules affected?
- In SwiftUI/MVVM equivalent, **yes**:
- `28` ViewModel classes in project
- `99` view/viewmodel/service declarations that can be impacted by orchestration shifts
- One hub file `SupabaseManager.swift` (`4216` LOC) introduces high coupling ripple risk

## Top-Risk Modules (must refactor carefully)
1. `antios5/Core/Networking/SupabaseManager.swift`
2. `antios5/Features/Dashboard/DashboardView.swift`
3. `antios5/Features/Dashboard/DashboardViewModel.swift`
4. `antios5/Features/Calibration/CalibrationViewModel.swift`
5. `antios5/Features/Max/MaxChatViewModel.swift`
6. `antios5/Features/Onboarding/ClinicalOnboardingView.swift`
7. `antios5/Features/Report/ReportViewModels.swift`
8. `antios5/Core/HealthKit/HealthKitService.swift`

## Suggested Execution Sequence
1. Freeze target contracts (anti-anxiety data schema + wearable ingestion contract)
2. Rewrite home orchestration around the 4-step loop
3. Connect HealthKit -> backend persistence -> profile enrichment
4. Tighten Max response format with evidence attribution
5. Re-bind plan/task closure and add loop-level regression checks
