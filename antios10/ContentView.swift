import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var appSettings: AppSettings
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false

    var body: some View {
        Group {
            if !supabase.isSessionRestored {
                A10LaunchView(language: appSettings.language)
            } else if !supabase.isAuthenticated {
                AuthView()
            } else if !supabase.isClinicalComplete {
                ClinicalOnboardingView(isComplete: $supabase.isClinicalComplete)
            } else if !isOnboardingComplete {
                OnboardingView(isComplete: $isOnboardingComplete)
            } else {
                A10AppShell(language: appSettings.language)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: supabase.isSessionRestored)
        .animation(.easeInOut(duration: 0.24), value: supabase.isAuthenticated)
        .animation(.easeInOut(duration: 0.24), value: isOnboardingComplete)
    }
}

func A10NonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private struct A10AppShell: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var syncCoordinator = A10ShellSyncCoordinator()
    @StateObject private var maxChatViewModel = MaxChatViewModel()
    @State private var selectedTab: A10Tab = .home
    #if DEBUG
    @AppStorage("debug_max_command") private var debugMaxCommand = ""
    @AppStorage("debug_max_batch_file") private var debugMaxBatchFile = ""
    #endif

    let language: AppLanguage

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                A10HomeView(
                    language: language,
                    onOpenMax: { selectedTab = .max }
                )
            }
            .tabItem {
                Label(
                    A10Tab.home.title(language: language),
                    systemImage: A10Tab.home.icon
                )
            }
            .tag(A10Tab.home)

            NavigationStack {
                MaxChatView(viewModel: maxChatViewModel)
            }
            .tabItem {
                Label(
                    A10Tab.max.title(language: language),
                    systemImage: A10Tab.max.icon
                )
            }
            .tag(A10Tab.max)

            NavigationStack {
                A10MeView(language: language)
            }
            .tabItem {
                Label(
                    A10Tab.me.title(language: language),
                    systemImage: A10Tab.me.icon
                )
            }
            .tag(A10Tab.me)
        }
        .task(id: language.rawValue) {
            A10SeedData.ensureSeedData(context: modelContext, language: language)
            await syncCoordinator.sync(context: modelContext, language: language, force: false, trigger: "shell")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMaxChat)) { _ in
            selectedTab = .max
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in
            selectedTab = .home
        }
        #if DEBUG
        .onAppear {
            processDebugMaxCommand(debugLaunchMaxCommand)
            processDebugMaxCommand(debugMaxCommand)
            processDebugMaxBatch(debugLaunchMaxBatchFile)
            processDebugMaxBatch(debugMaxBatchFile)
        }
        .onChange(of: debugMaxCommand) { _, newValue in
            processDebugMaxCommand(newValue)
        }
        .onChange(of: debugMaxBatchFile) { _, newValue in
            processDebugMaxBatch(newValue)
        }
        #endif
        .environmentObject(syncCoordinator)
        .tint(A10Palette.brand)
        .background {
            AuroraBackground()
        }
    }

    #if DEBUG
    private var debugLaunchMaxCommand: String {
        let prefix = "-debug-max-command="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return ""
        }
        return String(argument.dropFirst(prefix.count))
    }

    private var debugLaunchMaxBatchFile: String {
        let prefix = "-debug-max-batch-file="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return ""
        }
        return String(argument.dropFirst(prefix.count))
    }

    private func processDebugMaxCommand(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        switch command {
        case "open":
            selectedTab = .max
        case "close":
            selectedTab = .home
        case "home":
            selectedTab = .home
        default:
            if command.hasPrefix("ask:") {
                let question = String(command.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                selectedTab = .max
                if !question.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(
                            name: .askMax,
                            object: nil,
                            userInfo: ["question": question]
                        )
                    }
                }
            }
        }

        DispatchQueue.main.async {
            if debugMaxCommand == rawCommand {
                debugMaxCommand = ""
            }
        }
    }

    private func processDebugMaxBatch(_ rawFilePath: String) {
        let filePath = rawFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filePath.isEmpty else { return }

        let prompts: [String]
        do {
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            prompts = contents
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            print("[MaxDebugBatch] failed to read prompts file: \(filePath) error=\(error.localizedDescription)")
            return
        }

        guard !prompts.isEmpty else {
            print("[MaxDebugBatch] prompts file is empty: \(filePath)")
            return
        }

        selectedTab = .max
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            maxChatViewModel.startDebugBatch(prompts: prompts, source: filePath)
        }

        DispatchQueue.main.async {
            if debugMaxBatchFile == rawFilePath {
                debugMaxBatchFile = ""
            }
        }
    }
    #endif
}

private struct A10HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.screenMetrics) private var metrics
    @EnvironmentObject private var syncCoordinator: A10ShellSyncCoordinator
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @Query(sort: \A10ActionPlan.sortOrder) private var plans: [A10ActionPlan]

    let language: AppLanguage
    let onOpenMax: () -> Void

    private var currentSnapshot: A10LoopSnapshot? { loopSnapshots.first }
    private var activePlansCount: Int { plans.filter { !$0.isCompleted }.count }
    private var completedPlansCount: Int { plans.filter(\.isCompleted).count }
    private var remoteContext: A10ShellRemoteContext? { syncCoordinator.remoteContext }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                A10ShellPageHeader(
                    eyebrow: L10n.text("今日状态", "Today", language: language),
                    title: A10Tab.home.title(language: language),
                    subtitle: homeHeaderSubtitle,
                    badgeTitle: homeHeaderBadgeTitle,
                    badgeTint: homeHeaderBadgeTint
                ) {
                    A10HeaderRefreshControl(isSyncing: syncCoordinator.isSyncing) {
                        Task {
                            await syncCoordinator.sync(
                                context: modelContext,
                                language: language,
                                force: true,
                                trigger: "home_header_refresh"
                            )
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                        if let currentSnapshot {
                            A10HomeOverviewCard(
                                snapshot: currentSnapshot,
                                activePlansCount: activePlansCount,
                                completedPlansCount: completedPlansCount,
                                language: language
                            )
                            A10DashboardSpatialHeroCard(
                                model: spatialDashboardModel(snapshot: currentSnapshot),
                                language: language,
                                onPrimaryAction: handleHeroPrimaryAction,
                                onSecondaryAction: handleHeroSecondaryAction
                            )
                        } else {
                            A10EmptyStateCard(
                                title: L10n.text("正在整理今天重点", "Preparing today's overview", language: language),
                                message: L10n.text("正在同步你的最新状态和建议。", "Syncing your latest state and guidance.", language: language)
                            )
                        }

                        A10SectionHeader(
                            title: L10n.text("当前进度", "Current progress", language: language),
                            subtitle: L10n.text("先让你知道现在最适合做什么。", "Show what fits you best right now.", language: language)
                        )

                        A10Card {
                            VStack(spacing: 14) {
                                ForEach(A10LoopStage.allCases) { stage in
                                    A10LoopStepRow(
                                        stage: stage,
                                        currentStage: currentSnapshot?.stage ?? .inquiry,
                                        language: language
                                    )
                                }
                            }
                        }

                        A10SectionHeader(
                            title: L10n.text("今日行动", "Today plan", language: language),
                            subtitle: L10n.text("把建议收敛成最小动作。", "Turn guidance into the smallest useful action.", language: language)
                        )

                        VStack(spacing: 12) {
                            ForEach(plans.prefix(3), id: \.persistentModelID) { plan in
                                A10ActionCard(
                                    plan: plan,
                                    language: language,
                                    onToggle: { toggle(plan: plan) }
                                )
                            }
                        }

                        A10SectionHeader(
                            title: L10n.text("快速动作", "Quick actions", language: language),
                            subtitle: L10n.text("先完成眼前这一步，再决定要不要继续。", "Finish the step in front of you, then decide whether to go deeper.", language: language)
                        )

                        LazyVGrid(columns: homeQuickActionColumns, alignment: .leading, spacing: 12) {
                            homeQuickActionAdvanceButton
                            homeQuickActionMaxButton
                        }
                    }
                    .frame(maxWidth: metrics.maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 0)
                    .padding(.bottom, metrics.bottomContentInset)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "home_refresh")
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func advanceLoop() {
        guard let snapshot = currentSnapshot else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        snapshot.stage = snapshot.stage.next
        snapshot.updatedAt = .now

        if snapshot.stage == .evidence {
            snapshot.evidenceNote = L10n.text(
                "先按你现在的状态继续，下一次同步会补充更多依据和建议。",
                "Keep going with your current state first. The next sync will add more context and guidance.",
                language: language
            )
        }

        if snapshot.stage == .action {
            snapshot.nextActionTitle = L10n.text("完成 3 分钟呼吸", "Complete a 3-minute breathing reset", language: language)
            snapshot.nextActionDetail = L10n.text("只做一个最低阻力动作，先把身体带回安全感。", "Do one lowest-friction action and bring the body back to safety first.", language: language)
            if !plans.contains(where: { $0.title == snapshot.nextActionTitle }) {
                modelContext.insert(
                    A10ActionPlan(
                        title: snapshot.nextActionTitle,
                        detail: snapshot.nextActionDetail,
                        effortLabel: L10n.text("低负担", "Low load", language: language),
                        estimatedMinutes: 3,
                        sortOrder: plans.count
                    )
                )
            }
        }

        try? modelContext.save()
        Task {
            await syncCoordinator.sync(context: modelContext, language: language, force: false, trigger: "loop_advance")
        }
    }

    private func toggle(plan: A10ActionPlan) {
        UISelectionFeedbackGenerator().selectionChanged()
        plan.isCompleted.toggle()
        plan.updatedAt = .now
        try? modelContext.save()
        Task {
            await syncCoordinator.syncPlanToggle(plan, context: modelContext, language: language)
        }
    }

    private var homeQuickActionColumns: [GridItem] {
        let minimumWidth: CGFloat = metrics.fixedScreenWidth <= 360 ? 156 : 168
        return [GridItem(.adaptive(minimum: minimumWidth), spacing: 12, alignment: .top)]
    }

    private var homeQuickActionAdvanceButton: some View {
        Button {
            advanceLoop()
        } label: {
            A10ActionButtonLabel(
                title: L10n.text("推进下一步", "Advance next step", language: language),
                subtitle: L10n.text("更新今天的进度", "Update today's progress", language: language),
                systemImage: "arrow.right.circle.fill"
            )
        }
        .buttonStyle(A10PrimaryButtonStyle())
    }

    private var homeQuickActionMaxButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onOpenMax()
        } label: {
            A10ActionButtonLabel(
                title: L10n.text("打开 Max", "Open Max", language: language),
                subtitle: L10n.text("直接和 Max 聊，继续下一步", "Talk to Max and continue the next step", language: language),
                systemImage: "bubble.left.and.bubble.right.fill"
            )
        }
        .buttonStyle(A10SecondaryButtonStyle())
    }

    private var homeHeaderSubtitle: String {
        if syncCoordinator.isSyncing {
            return L10n.text(
                "正在同步今天的状态和安排",
                "Syncing today's state and plans",
                language: language
            )
        }

        if syncCoordinator.lastSyncAt != nil {
            return L10n.text(
                "今天的状态和建议已同步",
                "Today's state and guidance are ready",
                language: language
            )
        }

        return L10n.text(
            "等待首次同步",
            "Waiting for first sync",
            language: language
        )
    }

    private var homeHeaderBadgeTitle: String {
        if syncCoordinator.isSyncing {
            return L10n.text("同步中", "Syncing", language: language)
        }

        if syncCoordinator.lastSyncAt != nil {
            return L10n.text("已接入", "Connected", language: language)
        }

        return L10n.text("待同步", "Pending", language: language)
    }

    private var homeHeaderBadgeTint: Color {
        if syncCoordinator.isSyncing {
            return A10Palette.info
        }

        if syncCoordinator.lastSyncAt != nil {
            return A10Palette.success
        }

        return A10Palette.warning
    }

    private struct A10CompositeTrendPoint {
        let date: Date
        let compositeScore: Double
        let sleepScore: Double
        let calmScore: Double
        let tensionScore: Double
        let clarityScore: Double
        let regulationScore: Double
    }

    private func spatialDashboardModel(snapshot: A10LoopSnapshot) -> A10DashboardSpatialHeroModel {
        let trendPoints = compositeTrendPoints(snapshot: snapshot)
        let currentPoint = trendPoints.last ?? fallbackTrendPoint(snapshot: snapshot)
        let currentScore = Int(currentPoint.compositeScore.rounded())
        let trendDelta = trendPoints.count > 1
            ? Int((currentPoint.compositeScore - trendPoints.first!.compositeScore).rounded())
            : 0
        let remoteStress = remoteContext?.effectiveStressScore ?? snapshot.stressScore
        let dataCoverage = "\(trendPoints.count)/7"
        let focusTitle = remoteContext?.focusText ?? snapshot.stage.title(language: language)
        let deltaPrefix = trendDelta > 0 ? "+" : ""

        return A10DashboardSpatialHeroModel(
            eyebrow: remoteContext?.focusText != nil
                ? A10LocalizedText(zh: "状态趋势", en: "State trend")
                : A10LocalizedText(zh: "近 7 天趋势", en: "7-day trend"),
            topMetrics: [
                A10SpatialMetric(
                    id: "score",
                    title: A10LocalizedText(zh: "当前状态", en: "Current score"),
                    value: "\(currentScore)"
                ),
                A10SpatialMetric(
                    id: "trend_delta",
                    title: A10LocalizedText(zh: "7 日变化", en: "7d delta"),
                    value: "\(deltaPrefix)\(trendDelta)"
                )
            ],
            chart: A10AuraLineChartModel(
                values: trendPoints.map(\.compositeScore),
                minValue: 0,
                maxValue: 100,
                xLabels: trendPoints.map(axisLabel(for:)),
                yLabels: ["100", "75", "50", "25", "0"],
                annotations: trendAnnotations(points: trendPoints, currentScore: currentScore, trendDelta: trendDelta)
            ),
            primaryActionTitle: heroPrimaryActionTitle(),
            secondaryActionSymbol: heroSecondaryActionSymbol(stressScore: remoteStress),
            footerTitle: A10LocalizedText(zh: "趋势波纹", en: "Trend ripple"),
            bottomMetrics: [
                A10SpatialMetric(
                    id: "focus",
                    title: A10LocalizedText(zh: "当前焦点", en: "Current focus"),
                    value: focusTitle
                ),
                A10SpatialMetric(
                    id: "coverage",
                    title: A10LocalizedText(zh: "数据覆盖", en: "Coverage"),
                    value: dataCoverage
                )
            ],
            waveSamples: denseWaveSamples(from: trendPoints)
        )
    }

    private func trendAnnotations(
        points: [A10CompositeTrendPoint],
        currentScore: Int,
        trendDelta: Int
    ) -> [A10AuraChartAnnotation] {
        guard !points.isEmpty else { return [] }

        var annotations = [
            A10AuraChartAnnotation(
                id: "current_score",
                pointIndex: points.count - 1,
                text: A10LocalizedText(
                    zh: "今天 \(currentScore)",
                    en: "Today \(currentScore)"
                ),
                xOffset: -26,
                yOffset: -18
            )
        ]

        if points.count > 1 {
            let deltaPrefix = trendDelta > 0 ? "+" : ""
            annotations.append(
                A10AuraChartAnnotation(
                    id: "trend_delta",
                    pointIndex: max(points.count - 3, 0),
                    text: A10LocalizedText(
                        zh: "7 天 \(deltaPrefix)\(trendDelta)",
                        en: "7d \(deltaPrefix)\(trendDelta)"
                    ),
                    xOffset: 26,
                    yOffset: -48
                )
            )
        }

        return annotations
    }

    private func denseWaveSamples(from points: [A10CompositeTrendPoint]) -> [CGFloat] {
        let source = points.map(\.compositeScore)
        guard !source.isEmpty else { return Array(repeating: 0.28, count: 24) }
        if source.count == 1 {
            let base = CGFloat(min(max(source[0] / 100, 0.18), 0.84))
            return (0..<24).map { index in
                let shimmer = sin(CGFloat(index) * 0.62) * 0.05 + cos(CGFloat(index) * 0.18) * 0.03
                return min(max(base + shimmer, 0.14), 0.88)
            }
        }

        let barCount = 26
        return (0..<barCount).map { index in
            let progress = Double(index) / Double(max(barCount - 1, 1))
            let scaled = progress * Double(source.count - 1)
            let lower = Int(floor(scaled))
            let upper = min(lower + 1, source.count - 1)
            let localT = scaled - Double(lower)
            let interpolated = source[lower] + (source[upper] - source[lower]) * localT
            let slope = abs(source[upper] - source[lower]) / 100
            let base = 0.16 + (interpolated / 100) * 0.48
            let ripple = sin(Double(index) * 0.58) * 0.055 + cos(Double(index) * 0.21) * 0.03
            let envelope = sin(progress * Double.pi * 1.45 - 0.55) * 0.045
            let accent = slope * 0.18
            return CGFloat(min(max(base + ripple + envelope + accent, 0.12), 0.9))
        }
    }

    private func compositeTrendPoints(snapshot: A10LoopSnapshot) -> [A10CompositeTrendPoint] {
        guard let dashboard = remoteContext?.dashboard else {
            return [fallbackTrendPoint(snapshot: snapshot)]
        }

        let groupedLogs = Dictionary(grouping: dashboard.weeklyLogs) { normalizedDayKey(from: $0.log_date) ?? $0.log_date }
        let sortedLogs = groupedLogs.values.compactMap { logs -> (Date, WellnessLog)? in
            guard let first = logs.first,
                  let date = normalizedDayDate(from: first.log_date) else { return nil }
            let chosen = logs.max { lhs, rhs in
                metricPresenceCount(log: lhs) < metricPresenceCount(log: rhs)
            } ?? first
            return (date, chosen)
        }
        .sorted { $0.0 < $1.0 }

        let habitCompletion = currentHabitCompletionScore()
        let recent = sortedLogs.suffix(7).map { date, log in
            compositeTrendPoint(
                date: date,
                log: log,
                hardware: shouldBlendHardware(into: date) ? dashboard.hardwareData : nil,
                habitCompletion: shouldBlendHardware(into: date) ? habitCompletion : nil
            )
        }

        if recent.isEmpty {
            return [fallbackTrendPoint(snapshot: snapshot)]
        }

        return recent
    }

    private func compositeTrendPoint(
        date: Date,
        log: WellnessLog,
        hardware: HardwareData?,
        habitCompletion: Double?
    ) -> A10CompositeTrendPoint {
        let sleepScore = weightedAverage([
            (sleepDurationScore(log.sleep_duration_minutes), 0.7),
            (sleepQualityScore(log.sleep_quality), 0.3)
        ]) ?? 52

        let calmScore = weightedAverage([
            (inverseTenScale(log.anxiety_level), 0.45),
            (hrvScore(hardware?.hrv?.value), 0.3),
            (restingHeartRateScore(hardware?.resting_heart_rate?.value), 0.25)
        ]) ?? 50

        let tensionScore = weightedAverage([
            (inverseTenScale(log.stress_level), 0.55),
            (inverseTenScale(log.body_tension), 0.45)
        ]) ?? 50

        let clarityScore = weightedAverage([
            (positiveTenScale(log.mental_clarity), 0.4),
            (readinessScore(log.overall_readiness), 0.4),
            (positiveTenScale(log.morning_energy), 0.2)
        ]) ?? 52

        let regulationScore = weightedAverage([
            (minutesScore(log.exercise_duration_minutes, target: 30), 0.35),
            (minutesScore(log.mindfulness_minutes, target: 12), 0.35),
            (stepsScore(hardware?.steps?.value), 0.2),
            (habitCompletion, 0.1)
        ]) ?? 45

        let compositeScore = weightedAverage([
            (sleepScore, 0.24),
            (calmScore, 0.24),
            (tensionScore, 0.18),
            (clarityScore, 0.22),
            (regulationScore, 0.12)
        ]) ?? 50

        return A10CompositeTrendPoint(
            date: date,
            compositeScore: compositeScore,
            sleepScore: sleepScore,
            calmScore: calmScore,
            tensionScore: tensionScore,
            clarityScore: clarityScore,
            regulationScore: regulationScore
        )
    }

    private func fallbackTrendPoint(snapshot: A10LoopSnapshot) -> A10CompositeTrendPoint {
        let inverseStress = min(max((10 - Double(snapshot.stressScore)) / 10 * 100, 0), 100)
        let regulation = currentHabitCompletionScore() ?? 42
        let clarity = min(100, max(35, inverseStress * 0.72 + 18))
        let sleep = min(100, max(40, inverseStress * 0.64 + 22))
        let composite = weightedAverage([
            (sleep, 0.24),
            (inverseStress, 0.24),
            (inverseStress, 0.18),
            (clarity, 0.22),
            (regulation, 0.12)
        ]) ?? 50

        return A10CompositeTrendPoint(
            date: snapshot.updatedAt,
            compositeScore: composite,
            sleepScore: sleep,
            calmScore: inverseStress,
            tensionScore: inverseStress,
            clarityScore: clarity,
            regulationScore: regulation
        )
    }

    private func axisLabel(for point: A10CompositeTrendPoint) -> A10LocalizedText {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        let label = formatter.string(from: point.date)
        return A10LocalizedText(zh: label, en: label)
    }

    private func shouldBlendHardware(into date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func currentHabitCompletionScore() -> Double? {
        let remoteTotal = remoteContext?.habits.count ?? 0
        let remoteCompleted = remoteContext?.completedHabitsCount ?? 0
        if remoteTotal > 0 {
            return (Double(remoteCompleted) / Double(remoteTotal)) * 100
        }

        let localTotal = plans.count
        guard localTotal > 0 else { return nil }
        return (Double(completedPlansCount) / Double(localTotal)) * 100
    }

    private func normalizedDayKey(from raw: String) -> String? {
        let prefix = String(raw.prefix(10))
        return prefix.isEmpty ? nil : prefix
    }

    private func normalizedDayDate(from raw: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return Calendar.current.startOfDay(for: date)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(raw.prefix(10))) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    private func metricPresenceCount(log: WellnessLog) -> Int {
        [
            log.sleep_duration_minutes != nil,
            log.sleep_quality != nil,
            log.stress_level != nil,
            log.body_tension != nil,
            log.anxiety_level != nil,
            log.mental_clarity != nil,
            log.morning_energy != nil,
            log.overall_readiness != nil,
            log.exercise_duration_minutes != nil,
            log.mindfulness_minutes != nil
        ]
        .filter { $0 }
        .count
    }

    private func weightedAverage(_ entries: [(Double?, Double)]) -> Double? {
        let resolved = entries.compactMap { value, weight -> (Double, Double)? in
            guard let value else { return nil }
            return (value, weight)
        }
        guard !resolved.isEmpty else { return nil }

        let totalWeight = resolved.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }

        let total = resolved.reduce(0) { partial, entry in
            partial + entry.0 * entry.1
        }
        return total / totalWeight
    }

    private func positiveTenScale(_ value: Int?) -> Double? {
        guard let value else { return nil }
        return min(max(Double(value), 0), 10) * 10
    }

    private func inverseTenScale(_ value: Int?) -> Double? {
        guard let value else { return nil }
        return (10 - min(max(Double(value), 0), 10)) * 10
    }

    private func readinessScore(_ value: Int?) -> Double? {
        guard let value else { return nil }
        let normalized = value <= 10 ? Double(value) * 10 : Double(value)
        return min(max(normalized, 0), 100)
    }

    private func sleepDurationScore(_ minutes: Int?) -> Double? {
        guard let minutes else { return nil }
        return min(max(Double(minutes) / 480 * 100, 0), 100)
    }

    private func sleepQualityScore(_ value: String?) -> Double? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        if let numeric = Double(raw) {
            if numeric <= 5 {
                return min(max(numeric / 5 * 100, 0), 100)
            }
            if numeric <= 10 {
                return min(max(numeric * 10, 0), 100)
            }
            return min(max(numeric, 0), 100)
        }

        switch raw.lowercased() {
        case "excellent", "great":
            return 95
        case "good":
            return 80
        case "okay", "ok", "neutral", "average":
            return 65
        case "fair":
            return 55
        case "poor", "bad":
            return 35
        case "terrible":
            return 20
        default:
            return nil
        }
    }

    private func minutesScore(_ value: Int?, target: Double) -> Double? {
        guard let value else { return nil }
        return min(max(Double(value) / target * 100, 0), 100)
    }

    private func stepsScore(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max(value / 8000 * 100, 0), 100)
    }

    private func hrvScore(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max((value - 15) / 45 * 100, 0), 100)
    }

    private func restingHeartRateScore(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max((90 - value) / 35 * 100, 0), 100)
    }

    private func heroPrimaryActionTitle() -> A10LocalizedText {
        if remoteContext?.pendingInquiry != nil {
            return A10LocalizedText(zh: "回答问题", en: "Answer question")
        }
        if remoteContext?.hasActivePlan == true || activePlansCount > 0 {
            return A10LocalizedText(zh: "推进计划", en: "Continue plan")
        }
        if remoteContext?.proactiveBrief != nil {
            return A10LocalizedText(zh: "查看关怀", en: "Open care brief")
        }
        if remoteContext?.hasSignals == false {
            return A10LocalizedText(zh: "记录状态", en: "Record state")
        }
        return A10LocalizedText(zh: "进入 Max", en: "Open Max")
    }

    private func heroSecondaryActionSymbol(stressScore: Int) -> String {
        if stressScore >= 7 {
            return "wind"
        }
        if remoteContext?.hasActivePlan == true || activePlansCount > 0 {
            return "checklist"
        }
        if remoteContext?.pendingInquiry != nil {
            return "questionmark.bubble"
        }
        return "arrow.clockwise"
    }

    private func handleHeroPrimaryAction() {
        UISelectionFeedbackGenerator().selectionChanged()

        let summary: String
        if let remoteContext {
            if remoteContext.pendingInquiry != nil {
                summary = "pending_inquiry"
                openMaxFromHero(intent: "inquiry")
            } else if remoteContext.hasActivePlan {
                summary = remoteContext.activePlan?.title ?? "active_plan"
                openMaxFromHero(intent: "plan_review")
            } else if remoteContext.proactiveBrief != nil {
                summary = remoteContext.proactiveBrief?.title ?? "proactive_brief"
                openMaxFromHero(intent: "proactive_brief")
            } else if !remoteContext.hasSignals {
                summary = "start_check_in"
                triggerMaxExecutionFromHero(.startCalibration)
            } else {
                summary = "body_signal_follow_up"
                openMaxFromHero(intent: "body_signal")
            }
        } else {
            summary = "open_max"
            onOpenMax()
        }

        Task {
            await SupabaseManager.shared.captureUserSignal(
                domain: "a10_shell",
                action: "hero_primary_tapped",
                summary: summary,
                metadata: [
                    "source": "a10_dashboard_hero",
                    "has_remote_context": remoteContext != nil
                ]
            )
        }
    }

    private func handleHeroSecondaryAction() {
        let stressScore = remoteContext?.effectiveStressScore ?? currentSnapshot?.stressScore ?? 6
        let summary: String

        if stressScore >= 7 {
            summary = "breathing_reset"
            triggerMaxExecutionFromHero(.startBreathing, userInfo: ["duration": 3])
        } else if remoteContext?.hasActivePlan == true || activePlansCount > 0 {
            summary = "plan_review"
            openMaxFromHero(intent: "plan_review")
        } else if remoteContext?.pendingInquiry != nil {
            summary = "pending_inquiry"
            openMaxFromHero(intent: "inquiry")
        } else {
            summary = "force_sync"
            Task {
                await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "home_hero_secondary")
            }
        }

        Task {
            await SupabaseManager.shared.captureUserSignal(
                domain: "a10_shell",
                action: "hero_secondary_tapped",
                summary: summary,
                metadata: [
                    "source": "a10_dashboard_hero",
                    "stress_score": stressScore
                ]
            )
        }
    }

    private func openMaxFromHero(intent: String? = nil, question: String? = nil) {
        onOpenMax()

        var payload: [AnyHashable: Any] = [:]
        if let intent { payload["intent"] = intent }
        if let question { payload["question"] = question }
        guard !payload.isEmpty else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            NotificationCenter.default.post(name: .askMax, object: nil, userInfo: payload)
        }
    }

    private func triggerMaxExecutionFromHero(
        _ notification: Notification.Name,
        userInfo: [AnyHashable: Any]? = nil
    ) {
        onOpenMax()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            NotificationCenter.default.post(name: notification, object: nil, userInfo: userInfo)
        }
    }
}

private struct A10MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.screenMetrics) private var metrics
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var syncCoordinator: A10ShellSyncCoordinator
    @EnvironmentObject private var themeManager: ThemeManager
    @Query(sort: \A10PreferenceRecord.updatedAt, order: .reverse) private var preferenceRecords: [A10PreferenceRecord]
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @Query(sort: \A10ActionPlan.sortOrder) private var plans: [A10ActionPlan]
    @State private var selectedEmotionShortcutID: String?

    let language: AppLanguage

    private var preferences: A10PreferenceRecord? { preferenceRecords.first }
    private var currentSnapshot: A10LoopSnapshot? { loopSnapshots.first }
    private var remoteContext: A10ShellRemoteContext? { syncCoordinator.remoteContext }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                A10ShellPageHeader(
                    eyebrow: L10n.text("我的概览", "Overview", language: language),
                    title: A10Tab.me.title(language: language),
                    subtitle: meHeaderSubtitle,
                    badgeTitle: meHeaderBadgeTitle,
                    badgeTint: meHeaderBadgeTint
                ) {
                    A10HeaderRefreshControl(isSyncing: syncCoordinator.isSyncing) {
                        Task {
                            await syncCoordinator.sync(
                                context: modelContext,
                                language: language,
                                force: true,
                                trigger: "me_header_refresh"
                            )
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                        A10MeOverviewCard(
                            snapshot: currentSnapshot,
                            preferences: preferences,
                            planCount: plans.count,
                            language: language,
                            isSyncing: syncCoordinator.isSyncing
                        )

                        A10EmotionWheelScaffold(
                            model: emotionWheelModel,
                            language: language,
                            selectedShortcutID: resolvedEmotionShortcutID,
                            onSelectShortcut: handleEmotionShortcut,
                            onSelectDockAction: handleEmotionDockAction
                        )

                        A10SectionHeader(
                            title: L10n.text("系统与偏好", "System and preferences", language: language),
                            subtitle: L10n.text("把设置和同步状态放在一起，少一点来回切换。", "Keep settings and sync status together in one place.", language: language)
                        )

                        A10Card {
                            VStack(spacing: 16) {
                                A10AppearanceModeRow(
                                    title: L10n.text("外观模式", "Appearance", language: language),
                                    subtitle: L10n.text("直接切换跟随系统、浅色或深色。", "Switch between system, light, and dark instantly.", language: language),
                                    selectedMode: themeManager.appearanceMode,
                                    language: language
                                ) { mode in
                                    themeManager.appearanceMode = mode
                                }

                                A10Divider()

                                A10SettingsToggleRow(
                                    title: L10n.text("Health 数据同步", "Health data sync", language: language),
                                    subtitle: L10n.text("保持 Apple Health 为首选输入来源。", "Keep Apple Health as the preferred signal source.", language: language),
                                    isOn: Binding(
                                        get: { preferences?.healthSyncEnabled ?? true },
                                        set: { newValue in
                                            updatePreferences { record in
                                                record.healthSyncEnabled = newValue
                                            }
                                        }
                                    )
                                )

                                A10Divider()

                                A10SettingsToggleRow(
                                    title: L10n.text("每日提醒", "Daily reminders", language: language),
                                    subtitle: L10n.text("仅保留高价值提醒，不制造噪音。", "Keep reminders high value and low noise.", language: language),
                                    isOn: Binding(
                                        get: { preferences?.notificationsEnabled ?? true },
                                        set: { newValue in
                                            updatePreferences { record in
                                                record.notificationsEnabled = newValue
                                            }
                                        }
                                    )
                                )
                            }
                        }

                        A10SectionHeader(
                            title: L10n.text("同步状态", "Sync status", language: language),
                            subtitle: L10n.text("看看本地记录、账号和建议是不是都正常。", "Check whether local data, account, and guidance are all in sync.", language: language)
                        )
                        A10Card {
                            VStack(spacing: 14) {
                                A10MetricRow(
                                    title: L10n.text("本地记录", "Local data", language: language),
                                    value: L10n.text("已正常保存", "Saving normally", language: language)
                                )
                                A10MetricRow(
                                    title: L10n.text("今日记录", "Today logs", language: language),
                                    value: "\(loopSnapshots.count)"
                                )
                                A10MetricRow(
                                    title: L10n.text("行动计划", "Plans", language: language),
                                    value: "\(plans.count)"
                                )
                                A10MetricRow(
                                    title: "Max",
                                    value: L10n.text("聊天、建议和计划都在这里", "Chat, guidance, and plans all live here", language: language)
                                )
                                A10MetricRow(
                                    title: L10n.text("已同步内容", "Synced items", language: language),
                                    value: L10n.text("首页、计划和 Max 已联通", "Home, plans, and Max are connected", language: language)
                                )
                            }
                        }

                        Button {
                            Task {
                                await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "me_manual_sync")
                            }
                        } label: {
                            A10ActionButtonLabel(
                                title: L10n.text("立即同步", "Sync now", language: language),
                                subtitle: L10n.text("刷新今天的状态、计划和建议", "Refresh today's state, plans, and guidance", language: language),
                                systemImage: "arrow.triangle.2.circlepath.circle.fill"
                            )
                        }
                        .buttonStyle(A10PrimaryButtonStyle())

                        A10SectionHeader(
                            title: L10n.text("账户", "Account", language: language),
                            subtitle: L10n.text("管理当前登录状态、提醒和退出操作。", "Manage sign-in, reminders, and sign-out here.", language: language)
                        )

                        A10Card {
                            VStack(alignment: .leading, spacing: 14) {
                                A10MetricRow(
                                    title: L10n.text("登录状态", "Sign-in", language: language),
                                    value: supabase.isAuthenticated
                                    ? L10n.text("已连接当前账户", "Connected to the current account", language: language)
                                    : L10n.text("当前未登录", "Not signed in", language: language)
                                )
                                A10MetricRow(
                                    title: L10n.text("通知", "Notifications", language: language),
                                    value: preferences?.notificationsEnabled == true
                                    ? L10n.text("已开启低噪提醒", "Low-noise reminders enabled", language: language)
                                    : L10n.text("暂未开启", "Currently off", language: language)
                                )

                                Button {
                                    Task { await supabase.signOut() }
                                } label: {
                                    A10ActionButtonLabel(
                                        title: L10n.text("退出登录", "Sign out", language: language),
                                        subtitle: L10n.text("保留本地记录，退出当前账户", "Keep local data and sign out of this account", language: language),
                                        systemImage: "rectangle.portrait.and.arrow.right"
                                    )
                                }
                                .buttonStyle(A10SecondaryButtonStyle())
                            }
                        }
                    }
                    .frame(maxWidth: metrics.maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 0)
                    .padding(.bottom, metrics.bottomContentInset)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "me_refresh")
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func updatePreferences(_ mutate: (A10PreferenceRecord) -> Void) {
        let record = preferences ?? A10SeedData.createPreferences(context: modelContext, language: language)
        mutate(record)
        record.languageCode = language.rawValue
        record.updatedAt = .now
        try? modelContext.save()
        Task {
            await syncCoordinator.syncPreferences(record, language: language)
        }
    }

    private var meHeaderSubtitle: String {
        if syncCoordinator.isSyncing {
            return L10n.text(
                "同步偏好与系统状态",
                "Syncing preferences and system state",
                language: language
            )
        }

        return L10n.text(
            "偏好与系统状态已对齐",
            "Preferences and system state are aligned",
            language: language
        )
    }

    private var meHeaderBadgeTitle: String {
        if syncCoordinator.isSyncing {
            return L10n.text("同步中", "Syncing", language: language)
        }

        if remoteContext != nil {
            return L10n.text("已就绪", "Ready", language: language)
        }

        return L10n.text("初始化", "Booting", language: language)
    }

    private var meHeaderBadgeTint: Color {
        if syncCoordinator.isSyncing {
            return A10Palette.info
        }

        if remoteContext != nil {
            return A10Palette.success
        }

        return A10Palette.brandSecondary
    }

    private var emotionWheelModel: A10EmotionWheelModel {
        let stressScore = remoteContext?.effectiveStressScore ?? currentSnapshot?.stressScore ?? 5
        let readinessScore = remoteContext?.readinessScore ?? 60
        let calmScore = min(10, max(1, 11 - stressScore + max(0, readinessScore - 60) / 20))
        let activeCount = max(
            plans.filter { !$0.isCompleted }.count,
            max(remoteContext?.openHabitsCount ?? 0, remoteContext?.hasActivePlan == true ? 1 : 0)
        )
        let completedCount = max(plans.filter(\.isCompleted).count, remoteContext?.completedHabitsCount ?? 0)
        let healthOn = preferences?.healthSyncEnabled ?? remoteContext?.hasSignals ?? true
        let remoteReminders = remoteContext?.profile?.reminder_preferences
        let remindersOn = preferences?.notificationsEnabled
            ?? [remoteReminders?.morning, remoteReminders?.evening, remoteReminders?.breathing]
                .compactMap { $0 }
                .contains(true)
        let focusScore = min(
            10,
            max(3, (remoteContext?.focusText != nil ? 5 : 0) + max(completedCount, (remoteContext?.activePlan?.progress ?? 0) / 20))
        )
        let signalScore = min(10, max(3, (remoteContext?.signalCount ?? (healthOn ? 4 : 1)) * 2))
        let quietScore = min(10, max(2, (remindersOn ? 6 : 4) + (stressScore <= 4 ? 2 : 0)))
        let planScore = min(
            10,
            max(2, activeCount + completedCount + min((remoteContext?.activePlan?.progress ?? 0) / 25, 3))
        )
        let trustScore = min(
            10,
            max(3, (remoteContext != nil ? 4 : 0) + (remoteContext?.profile != nil ? 2 : 0) + (remoteContext?.hasSignals == true ? 2 : 0))
        )
        let readyScore = min(
            10,
            max(3, (syncCoordinator.isSyncing ? 4 : 6) + (remoteContext?.proactiveBrief != nil ? 2 : 0) + (remoteContext?.pendingInquiry == nil ? 1 : 0))
        )
        let insightBody = emotionInsightBody()

        return A10EmotionWheelModel(
            brandTitle: "antios10",
            shortcuts: [
                A10EmotionShortcut(id: "state", symbol: "waveform.path.ecg", title: A10LocalizedText(zh: "状态", en: "State")),
                A10EmotionShortcut(id: "plan", symbol: "checklist", title: A10LocalizedText(zh: "计划", en: "Plans")),
                A10EmotionShortcut(id: "signal", symbol: "heart.fill", title: A10LocalizedText(zh: "信号", en: "Signals")),
                A10EmotionShortcut(id: "focus", symbol: "scope", title: A10LocalizedText(zh: "聚焦", en: "Focus")),
                A10EmotionShortcut(id: "max", symbol: "sparkles", title: A10LocalizedText(zh: "Max", en: "Max"))
            ],
            maxScore: 10,
            petals: [
                A10EmotionPetal(id: "calm", title: A10LocalizedText(zh: "平静", en: "Calm"), score: calmScore, intensity: 0.82, tint: A10SpatialPalette.wheelPetals[0]),
                A10EmotionPetal(id: "stress", title: A10LocalizedText(zh: "张力", en: "Tension"), score: max(1, stressScore), intensity: 0.74, tint: A10SpatialPalette.wheelPetals[1]),
                A10EmotionPetal(id: "focus", title: A10LocalizedText(zh: "专注", en: "Focus"), score: focusScore, intensity: 0.76, tint: A10SpatialPalette.wheelPetals[2]),
                A10EmotionPetal(id: "signals", title: A10LocalizedText(zh: "信号", en: "Signals"), score: signalScore, intensity: 0.72, tint: A10SpatialPalette.wheelPetals[3]),
                A10EmotionPetal(id: "quiet", title: A10LocalizedText(zh: "安静", en: "Quiet"), score: quietScore, intensity: 0.7, tint: A10SpatialPalette.wheelPetals[4]),
                A10EmotionPetal(id: "plans", title: A10LocalizedText(zh: "执行", en: "Execution"), score: planScore, intensity: 0.78, tint: A10SpatialPalette.wheelPetals[5]),
                A10EmotionPetal(id: "trust", title: A10LocalizedText(zh: "稳定", en: "Steady"), score: trustScore, intensity: 0.74, tint: A10SpatialPalette.wheelPetals[6]),
                A10EmotionPetal(id: "ready", title: A10LocalizedText(zh: "就绪", en: "Ready"), score: readyScore, intensity: 0.8, tint: A10SpatialPalette.wheelPetals[7])
            ],
            insight: A10InsightCardModel(
                eyebrow: A10LocalizedText(zh: "状态摘要", en: "State summary"),
                body: insightBody
            ),
            leadingDockAction: A10DockAction(id: "home", symbol: "house.fill", isPrimary: false),
            centerDockAction: A10DockAction(id: "max", symbol: "bubble.left.and.bubble.right.fill", isPrimary: true),
            trailingDockActions: [
                A10DockAction(id: "sync", symbol: "arrow.triangle.2.circlepath", isPrimary: false)
            ]
        )
    }

    private func handleEmotionDockAction(_ action: A10DockAction) {
        switch action.id {
        case "home":
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        case "max":
            NotificationCenter.default.post(name: .openMaxChat, object: nil)
        case "sync":
            Task {
                await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "me_wheel_sync")
            }
        default:
            break
        }
    }

    private var resolvedEmotionShortcutID: String {
        if let selectedEmotionShortcutID {
            return selectedEmotionShortcutID
        }
        if remoteContext?.pendingInquiry != nil {
            return "state"
        }
        if remoteContext?.hasActivePlan == true {
            return "plan"
        }
        if remoteContext?.hasSignals == false {
            return "signal"
        }
        if remoteContext?.focusText != nil {
            return "focus"
        }
        return "max"
    }

    private func emotionInsightBody() -> A10LocalizedText {
        if let proactiveBrief = remoteContext?.proactiveBrief {
            let text = "\(proactiveBrief.understanding) \(proactiveBrief.microAction)"
            return A10LocalizedText(zh: text, en: text)
        }
        if let inquiry = remoteContext?.pendingInquiry {
            return A10LocalizedText(
                zh: "待回答问题：\(inquiry.questionText)",
                en: "Question waiting: \(inquiry.questionText)"
            )
        }
        if let focus = remoteContext?.focusText {
            return A10LocalizedText(
                zh: "现在最值得先处理的是「\(focus)」，让 Max 先围绕它给你下一步。",
                en: "The most important thing right now is \"\(focus)\". Let Max build the next step around it."
            )
        }
        let fallback = currentSnapshot?.summary ?? "先看今天的状态，再决定要不要补记录或刷新数据。"
        return A10LocalizedText(
            zh: fallback,
            en: currentSnapshot?.summary ?? "Review today's state first, then decide whether to add more detail or refresh data."
        )
    }

    private func handleEmotionShortcut(_ shortcut: A10EmotionShortcut) {
        selectedEmotionShortcutID = shortcut.id

        Task {
            await SupabaseManager.shared.captureUserSignal(
                domain: "a10_shell",
                action: "emotion_shortcut_tapped",
                summary: shortcut.id,
                metadata: [
                    "source": "a10_emotion_wheel"
                ]
            )
        }

        switch shortcut.id {
        case "state":
            if remoteContext?.pendingInquiry != nil {
                openMaxFromMe(intent: "inquiry")
            } else if remoteContext?.hasSignals == true {
                openMaxFromMe(intent: "body_signal")
            } else {
                triggerMaxExecutionFromMe(.startCalibration)
            }
        case "plan":
            if remoteContext?.hasActivePlan == true || plans.contains(where: { !$0.isCompleted }) {
                openMaxFromMe(intent: "plan_review")
            } else {
                openMaxFromMe(
                    question: L10n.text(
                        "请基于我当前状态，给我一个今天 10 分钟内可以完成的动作。",
                        "Based on my current state, give me one action I can complete within 10 minutes today.",
                        language: language
                    )
                )
            }
        case "signal":
            Task {
                await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "me_shortcut_signal")
            }
            if remoteContext?.hasSignals == true {
                openMaxFromMe(intent: "body_signal")
            } else {
                triggerMaxExecutionFromMe(.startCalibration)
            }
        case "focus":
            if let focus = remoteContext?.focusText {
                openMaxFromMe(
                    question: language == .en
                        ? "Use my current focus \"\(focus)\" to decide the next smallest action and one follow-up question."
                        : "请围绕我当前焦点「\(focus)」决定下一步最小动作，并给我一个跟进问题。"
                )
            } else {
                NotificationCenter.default.post(name: .openDashboard, object: nil)
            }
        case "max":
            NotificationCenter.default.post(name: .openMaxChat, object: nil)
        default:
            break
        }
    }

    private func openMaxFromMe(intent: String? = nil, question: String? = nil) {
        NotificationCenter.default.post(name: .openMaxChat, object: nil)

        var payload: [AnyHashable: Any] = [:]
        if let intent { payload["intent"] = intent }
        if let question { payload["question"] = question }
        guard !payload.isEmpty else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            NotificationCenter.default.post(name: .askMax, object: nil, userInfo: payload)
        }
    }

    private func triggerMaxExecutionFromMe(
        _ notification: Notification.Name,
        userInfo: [AnyHashable: Any]? = nil
    ) {
        NotificationCenter.default.post(name: .openMaxChat, object: nil)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            NotificationCenter.default.post(name: notification, object: nil, userInfo: userInfo)
        }
    }
}

private struct A10ShellPageHeader<Trailing: View>: View {
    @Environment(\.screenMetrics) private var metrics

    let eyebrow: String
    let title: String
    let subtitle: String
    let badgeTitle: String?
    let badgeTint: Color
    let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        badgeTitle: String? = nil,
        badgeTint: Color = A10Palette.brand,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.badgeTitle = badgeTitle
        self.badgeTint = badgeTint
        self.trailing = trailing()
    }

    private var contentTopInset: CGFloat {
        max(metrics.safeAreaInsets.top - 30, 6)
    }

    private var mistHeight: CGFloat {
        max(metrics.safeAreaInsets.top + 44, 74)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)

                    if let badgeTitle, !badgeTitle.isEmpty {
                        Text(badgeTitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(badgeTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(badgeTint.opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                }

                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing
                .padding(.top, 2)
        }
        .frame(maxWidth: metrics.maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, contentTopInset)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            badgeTint.opacity(0.08),
                            Color.white.opacity(0.03),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.78),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: mistHeight)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

private struct A10HeaderRefreshControl: View {
    let isSyncing: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isSyncing {
                ProgressView()
                    .tint(A10Palette.brand)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            } else {
                Button(action: action) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(A10Palette.ink)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct A10LaunchView: View {
    let language: AppLanguage

    var body: some View {
        ZStack {
            AuroraBackground()

            LiquidGlassCard(style: .elevated, padding: 32) {
                VStack(spacing: 18) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.brand)

                    Text("AntiAnxiety")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)

                    Text(
                        L10n.text(
                            "正在切换到更轻、更稳的 antios10 主壳层",
                            "Booting the lighter and steadier antios10 shell",
                            language: language
                        )
                    )
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
                    .multilineTextAlignment(.center)

                    ProgressView()
                        .tint(A10Palette.brand)
                        .padding(.top, 8)
                }
            }
            .padding(28)
        }
    }
}

private struct A10FocusHeroCard: View {
    let snapshot: A10LoopSnapshot
    let language: AppLanguage

    var body: some View {
        A10Card(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("今日重点", "Today's focus", language: language))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)

                Text(snapshot.headline)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)

                Text(snapshot.summary)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)

                HStack(spacing: 12) {
                    A10Badge(
                        title: "\(L10n.text("压力", "Stress", language: language)) \(snapshot.stressScore)/10",
                        tint: A10Palette.warning
                    )
                    A10Badge(
                        title: snapshot.stage.title(language: language),
                        tint: A10Palette.brand
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.nextActionTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                    Text(snapshot.nextActionDetail)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(A10Palette.inset)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(A10Palette.line.opacity(0.85), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct A10HomeOverviewCard: View {
    let snapshot: A10LoopSnapshot
    let activePlansCount: Int
    let completedPlansCount: Int
    let language: AppLanguage

    var body: some View {
        LiquidGlassCard(style: .standard, padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("恢复总览", "Recovery overview", language: language))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text(snapshot.stage.title(language: language))
                            .font(.system(size: 18, weight: .light, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                        Text(snapshot.evidenceNote)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(L10n.text("压力读数", "Stress reading", language: language))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text("\(snapshot.stressScore)/10")
                            .font(.system(size: 18, weight: .light, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        A10OverviewMetricCard(
                            title: L10n.text("当前", "Stage", language: language),
                            value: snapshot.stage.title(language: language),
                            detail: L10n.text("进度", "Progress", language: language),
                            tint: A10Palette.brand
                        )
                        A10OverviewMetricCard(
                            title: L10n.text("动作", "Plans", language: language),
                            value: "\(activePlansCount)",
                            detail: L10n.text("待执行", "Queued", language: language),
                            tint: A10Palette.info
                        )
                        A10OverviewMetricCard(
                            title: L10n.text("完成", "Done", language: language),
                            value: "\(completedPlansCount)",
                            detail: L10n.text("反馈", "Closed", language: language),
                            tint: A10Palette.success
                        )
                        A10OverviewMetricCard(
                            title: L10n.text("下一步", "Next", language: language),
                            value: snapshot.nextActionTitle,
                            detail: L10n.text("低阻力", "Low friction", language: language),
                            tint: A10Palette.brandSecondary,
                            width: 132
                        )
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(A10Palette.line.opacity(0.68), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct A10MeOverviewCard: View {
    let snapshot: A10LoopSnapshot?
    let preferences: A10PreferenceRecord?
    let planCount: Int
    let language: AppLanguage
    let isSyncing: Bool

    var body: some View {
        LiquidGlassCard(style: .elevated, padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("我的概览", "Overview", language: language))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text(L10n.text("antios10", "antios10", language: language))
                            .font(.system(size: 18, weight: .light, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                        Text(
                            isSyncing
                            ? L10n.text("数据正在更新", "Updating data", language: language)
                            : L10n.text("偏好和状态已经保持一致", "Preferences and status are aligned", language: language)
                        )
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                        .lineLimit(1)
                    }

                    Spacer()

                    A10Badge(
                        title: isSyncing
                        ? L10n.text("同步中", "Syncing", language: language)
                        : L10n.text("已就绪", "Ready", language: language),
                        tint: isSyncing ? A10Palette.info : A10Palette.success
                    )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        A10OverviewMetricCard(
                            title: L10n.text("阶段", "Stage", language: language),
                            value: snapshot?.stage.title(language: language) ?? "A10",
                            detail: L10n.text("体验重心", "Focus", language: language),
                            tint: A10Palette.brand
                        )
                        A10OverviewMetricCard(
                            title: L10n.text("语言", "Language", language: language),
                            value: preferences?.languageCode.uppercased() ?? language.rawValue.uppercased(),
                            detail: L10n.text("文案", "Copy", language: language),
                            tint: A10Palette.brandSecondary
                        )
                        A10OverviewMetricCard(
                            title: L10n.text("提醒", "Reminders", language: language),
                            value: preferences?.notificationsEnabled == true
                            ? L10n.text("开启", "On", language: language)
                            : L10n.text("关闭", "Off", language: language),
                            detail: L10n.text("高价值", "High value", language: language),
                            tint: A10Palette.warning
                        )
                        A10OverviewMetricCard(
                            title: L10n.text("计划数", "Plans", language: language),
                            value: "\(planCount)",
                            detail: L10n.text("已安排", "Ready", language: language),
                            tint: A10Palette.info
                        )
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(A10Palette.brand.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }
}

private struct A10LoopStepRow: View {
    let stage: A10LoopStage
    let currentStage: A10LoopStage
    let language: AppLanguage

    private var isComplete: Bool {
        A10LoopStage.allCases.firstIndex(of: stage).map { index in
            guard let currentIndex = A10LoopStage.allCases.firstIndex(of: currentStage) else { return false }
            return index < currentIndex
        } ?? false
    }

    private var isCurrent: Bool { currentStage == stage }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(indicatorColor.opacity(0.18))
                    .frame(width: 38, height: 38)

                Image(systemName: isComplete ? "checkmark" : stage.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(indicatorColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stage.title(language: language))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)

                Text(stage.summary(language: language))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(indicatorColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var indicatorColor: Color {
        if isComplete { return A10Palette.success }
        if isCurrent { return A10Palette.brand }
        return A10Palette.line
    }

    private var statusText: String {
        if isComplete {
            return L10n.text("完成", "Done", language: language)
        }
        if isCurrent {
            return L10n.text("当前", "Current", language: language)
        }
        return L10n.text("待处理", "Queued", language: language)
    }
}

private struct A10ActionCard: View {
    let plan: A10ActionPlan
    let language: AppLanguage
    let onToggle: () -> Void

    var body: some View {
        A10Card {
            HStack(alignment: .top, spacing: 14) {
                Button(action: onToggle) {
                    Image(systemName: plan.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(plan.isCompleted ? A10Palette.success : A10Palette.line)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                    Text(plan.detail)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                    HStack(spacing: 8) {
                        A10Badge(title: plan.effortLabel, tint: A10Palette.info)
                        A10Badge(
                            title: "\(plan.estimatedMinutes) \(L10n.text("分钟", "min", language: language))",
                            tint: A10Palette.brandSecondary
                        )
                    }
                }

                Spacer()
            }
        }
    }
}

private struct A10SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.ink)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
        }
    }
}

private struct A10EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        A10Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)
                Text(message)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }
        }
    }
}

private struct A10MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.ink)
        }
    }
}

private struct A10SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(A10Palette.brand)
        }
    }
}

private struct A10AppearanceModeRow: View {
    let title: String
    let subtitle: String
    let selectedMode: AppearanceMode
    let language: AppLanguage
    let onSelect: (AppearanceMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(mode)
                    } label: {
                        Text(modeTitle(mode))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedMode == mode ? Color.white.opacity(0.96) : A10Palette.inkSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(selectedMode == mode ? A10Palette.brand : A10Palette.inset.opacity(0.94))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedMode == mode ? A10Palette.brand.opacity(0.16) : A10Palette.line.opacity(0.72),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func modeTitle(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            return L10n.text("跟随系统", "System", language: language)
        case .light:
            return L10n.text("浅色", "Light", language: language)
        case .dark:
            return L10n.text("深色", "Dark", language: language)
        }
    }
}

private struct A10ActionButtonLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.8)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .opacity(0.65)
        }
        .frame(minHeight: 78)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct A10Card<Content: View>: View {
    let highlighted: Bool
    @ViewBuilder let content: Content

    init(highlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.highlighted = highlighted
        self.content = content()
    }

    var body: some View {
        LiquidGlassCard(style: highlighted ? .elevated : .standard, padding: 18) {
            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(highlighted ? A10Palette.brand.opacity(0.16) : A10Palette.line.opacity(0.72), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(highlighted ? 0.12 : 0.06),
            radius: highlighted ? 24 : 16,
            y: highlighted ? 14 : 10
        )
    }
}

private struct A10OverviewMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var width: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.ink)
                .lineLimit(width > 120 ? 2 : 1)

            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 52, alignment: .topLeading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(A10Palette.inset.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct A10Badge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            )
            .clipShape(Capsule())
    }
}

private struct A10Divider: View {
    var body: some View {
        Rectangle()
            .fill(A10Palette.line.opacity(0.7))
            .frame(height: 1)
    }
}

private struct A10PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonStyle(kind: .primary).makeBody(configuration: configuration)
    }
}

private struct A10SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonStyle(kind: .secondary).makeBody(configuration: configuration)
    }
}

private enum A10Palette {
    static let canvas = Color.bgPrimary
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#222426") : UIColor(hex: "#FFFFFF")
    })
    static let surfaceStrong = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#27292C") : UIColor(hex: "#F7F9F3")
    })
    static let inset = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#1A1B1D") : UIColor(hex: "#E8EEE2")
    })
    static let line = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#414547") : UIColor(hex: "#D7DDD2")
    })
    static let ink = Color.textPrimary
    static let inkSecondary = Color.textSecondary
    static let inkTertiary = Color.textTertiary
    static let brand = Color.liquidGlassAccent
    static let brandSecondary = Color.liquidGlassWarm
    static let success = Color.statusSuccess
    static let warning = Color.statusWarning
    static let info = Color.liquidGlassSecondary
}

private extension A10Tab {
    var icon: String {
        switch self {
        case .home: return "house"
        case .max: return "bubble.left.and.bubble.right"
        case .me: return "person.crop.circle"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .home:
            return L10n.text("首页", "Home", language: language)
        case .max:
            return "Max"
        case .me:
            return L10n.text("我的", "Me", language: language)
        }
    }
}

private extension Color {
    init(a10Hex hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

#Preview("A10 Shell") {
    A10AppShell(language: .en)
        .modelContainer(
            for: [
                A10LoopSnapshot.self,
                A10ActionPlan.self,
                A10MaxSession.self,
                A10MaxMessage.self,
                A10PreferenceRecord.self
            ],
            inMemory: true
        )
}
