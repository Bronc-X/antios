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
            processDebugA10Navigation(
                tabRawValue: debugLaunchA10Tab,
                shortcutRawValue: debugLaunchA10Shortcut
            )
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

    private var debugLaunchA10Tab: String {
        let prefix = "-debug-a10-tab="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return ""
        }
        return String(argument.dropFirst(prefix.count))
    }

    private var debugLaunchA10Shortcut: String {
        let prefix = "-debug-a10-shortcut="
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

    private func processDebugA10Navigation(
        tabRawValue: String,
        shortcutRawValue: String
    ) {
        let normalizedTab = tabRawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedShortcut = shortcutRawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalizedTab {
        case "home":
            selectedTab = .home
        case "me", "profile":
            selectedTab = .me
        case "max":
            selectedTab = .max
        default:
            break
        }

        guard !normalizedShortcut.isEmpty else { return }
        selectedTab = .me
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NotificationCenter.default.post(
                name: .debugOpenA10Shortcut,
                object: nil,
                userInfo: ["shortcutID": normalizedShortcut]
            )
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
    @State private var selectedProgressItem: A10HomeProgressItem?

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
                    EmptyView()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                        if let currentSnapshot {
                            A10DashboardSpatialHeroCard(
                                model: spatialDashboardModel(snapshot: currentSnapshot),
                                language: language,
                                onPrimaryAction: handleHeroPrimaryAction
                            )

                            A10SectionHeader(
                                title: L10n.text("当前进度", "Current progress", language: language),
                                subtitle: L10n.text("问题和后续动作都集中在这里，减少首页噪音。", "Questions and next actions stay here so home remains clean.", language: language)
                            )

                            A10Card {
                                VStack(spacing: 12) {
                                    ForEach(homeProgressItems(snapshot: currentSnapshot)) { item in
                                        Button {
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                            selectedProgressItem = item
                                        } label: {
                                            A10HomeProgressRow(item: item, language: language)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            A10HomeOverviewCard(
                                snapshot: currentSnapshot,
                                activePlansCount: activePlansCount,
                                completedPlansCount: completedPlansCount,
                                language: language
                            )

                            if let bayesianInsight = bayesianInsightModel(snapshot: currentSnapshot) {
                                A10SectionHeader(
                                    title: L10n.text("贝叶斯提升", "Bayesian uplift", language: language),
                                    subtitle: L10n.text("把先验、身体信号和证据权重压成一个更稳的判断。", "Compress priors, body signals, and evidence weight into one steadier judgment.", language: language)
                                )

                                A10BayesianInsightCard(
                                    insight: bayesianInsight,
                                    language: language
                                )
                            }

                            scienceSection
                        } else {
                            A10EmptyStateCard(
                                title: L10n.text("正在整理今天重点", "Preparing today's overview", language: language),
                                message: L10n.text("正在同步你的最新状态和建议。", "Syncing your latest state and guidance.", language: language)
                            )
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
        .sheet(item: $selectedProgressItem) { item in
            A10HomeProgressSheet(
                item: item,
                language: language,
                onPrimaryAction: { performProgressAction(item) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
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

    private var homeHeaderSubtitle: String {
        if syncCoordinator.isCoreSyncing {
            return L10n.text(
                "正在同步今天的核心状态和安排",
                "Syncing today's core state and plans",
                language: language
            )
        }

        if syncCoordinator.isEnrichmentSyncing && remoteContext != nil {
            return L10n.text(
                "核心状态已就绪，正在补充贝叶斯判断和科学期刊",
                "Core state is ready. Bayesian guidance and science journals are still loading.",
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
        if syncCoordinator.isCoreSyncing {
            return L10n.text("同步中", "Syncing", language: language)
        }

        if syncCoordinator.isEnrichmentSyncing {
            return L10n.text("补充中", "Enriching", language: language)
        }

        if syncCoordinator.lastSyncAt != nil {
            return L10n.text("已接入", "Connected", language: language)
        }

        return L10n.text("待同步", "Pending", language: language)
    }

    private var homeHeaderBadgeTint: Color {
        if syncCoordinator.isCoreSyncing {
            return A10Palette.info
        }

        if syncCoordinator.isEnrichmentSyncing {
            return A10Palette.brandSecondary
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
        let actionTitle = heroActionHeadline(snapshot: snapshot)
        let actionDetail = heroActionDetail(snapshot: snapshot)

        return A10DashboardSpatialHeroModel(
            eyebrow: A10LocalizedText(zh: "今日行动", en: "Today's action"),
            actionTitle: A10LocalizedText(zh: actionTitle, en: actionTitle),
            actionDetail: A10LocalizedText(zh: actionDetail, en: actionDetail),
            statusBadge: heroStatusBadge(),
            statusTint: heroStatusTint(),
            topMetrics: [
                A10SpatialMetric(
                    id: "score",
                    title: A10LocalizedText(zh: "状态分", en: "State"),
                    value: "\(currentScore)"
                ),
                A10SpatialMetric(
                    id: "trend_delta",
                    title: A10LocalizedText(zh: "变化", en: "Change"),
                    value: trendDeltaString(trendDelta)
                )
            ],
            chart: A10AuraLineChartModel(
                values: trendPoints.map(\.compositeScore),
                minValue: 0,
                maxValue: 100,
                xLabels: trendPoints.map(axisLabel(for:)),
                yLabels: ["100", "75", "50", "25", "0"],
                annotations: [],
                snapshots: trendSnapshots(points: trendPoints),
                interactionHint: A10LocalizedText(
                    zh: "点按或滑动折线，查看每天的变化。",
                    en: "Tap or drag the line to inspect each day."
                )
            ),
            waveSamples: denseWaveSamples(from: trendPoints)
        )
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

    private func trendSnapshots(points: [A10CompositeTrendPoint]) -> [A10AuraChartSnapshot] {
        points.enumerated().map { index, point in
            let dateLabel = axisLabel(for: point)
            let stateValue = "\(Int(point.compositeScore.rounded()))"
            let secondary: String

            if index == points.count - 1 {
                secondary = todayTrendMeaning(for: point)
            } else if point.compositeScore < 45 {
                secondary = L10n.text("波动偏大，今天先减负。", "The swing is large. Ease the load today.", language: language)
            } else if point.compositeScore < 65 {
                secondary = L10n.text("还在回稳，先做轻一点。", "Still stabilizing. Keep it light first.", language: language)
            } else {
                secondary = L10n.text("状态在回升，可以继续一小步。", "State is recovering. One small next step is enough.", language: language)
            }

            return A10AuraChartSnapshot(
                id: "trend_\(index)",
                xLabel: dateLabel,
                primaryValue: stateValue,
                secondaryValue: secondary
            )
        }
    }

    private func todayTrendMeaning(for point: A10CompositeTrendPoint) -> String {
        if point.compositeScore >= 70 {
            return L10n.text("今天可以推进一点，但先别加码。", "You can move a little today, but don't overdo it.", language: language)
        }
        if point.compositeScore >= 55 {
            return L10n.text("今天先做一个最轻的动作，再交给 Max。", "Do one light step first, then hand it to Max.", language: language)
        }
        return L10n.text("今天先缓一缓，让 Max 帮你收窄下一步。", "Take it slow today and let Max narrow the next step.", language: language)
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
            return A10LocalizedText(zh: "查看进度", en: "Review progress")
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

    private func heroActionHeadline(snapshot: A10LoopSnapshot) -> String {
        if remoteContext?.pendingInquiry != nil {
            return L10n.text(
                "当前状态已经初步收口，下一步会围绕一个关键变量继续判断。",
                "Your state is narrowed enough; the next step will refine one key variable.",
                language: language
            )
        }
        if remoteContext?.activePlan != nil, remoteContext?.hasActivePlan == true {
            return L10n.text(
                "今天已经有执行路径，继续一个最小动作就够了。",
                "Today's execution path is already in place. One small action is enough.",
                language: language
            )
        }
        if let brief = remoteContext?.proactiveBrief, !brief.microAction.isEmpty {
            return brief.understanding
        }
        if remoteContext?.hasSignals == false {
            return L10n.text("今天还缺少状态记录，先补一条最低负担记录。", "Today's state record is still missing. Start with the lightest note first.", language: language)
        }
        return snapshot.summary
    }

    private func heroActionDetail(snapshot: A10LoopSnapshot) -> String {
        if remoteContext?.pendingInquiry != nil {
            return L10n.text(
                "具体问题已经下沉到下面“当前进度”，首页只保留总览判断。",
                "The specific question has moved down into Current progress, while home keeps only the overview.",
                language: language
            )
        }
        if let activePlan = remoteContext?.activePlan, remoteContext?.hasActivePlan == true {
            return L10n.text("当前进度", "Current progress", language: language) + " \(activePlan.progress)%"
        }
        if let brief = remoteContext?.proactiveBrief {
            return brief.microAction
        }
        if remoteContext?.hasSignals == false {
            return L10n.text("问题会放到下面当前进度里继续问，首页只保留总览。", "Questions continue below in Current progress; home keeps only the overview.", language: language)
        }
        return snapshot.nextActionDetail
    }

    private func heroStatusBadge() -> A10LocalizedText? {
        if remoteContext?.pendingInquiry != nil {
            return A10LocalizedText(zh: "待回答", en: "Pending")
        }
        if remoteContext?.hasActivePlan == true {
            return A10LocalizedText(zh: "进行中", en: "In progress")
        }
        if remoteContext?.proactiveBrief != nil {
            return A10LocalizedText(zh: "Max 已准备", en: "Max ready")
        }
        if remoteContext?.hasSignals == false {
            return A10LocalizedText(zh: "先记录", en: "Start note")
        }
        return A10LocalizedText(zh: "已同步", en: "Synced")
    }

    private func heroStatusTint() -> Color {
        if remoteContext?.pendingInquiry != nil { return A10Palette.warning }
        if remoteContext?.hasActivePlan == true { return A10Palette.info }
        if remoteContext?.proactiveBrief != nil { return A10Palette.brand }
        if remoteContext?.hasSignals == false { return A10Palette.warning }
        return A10Palette.success
    }

    private func trendDeltaString(_ value: Int) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(value)"
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

    private var currentScienceArticles: [ScienceArticle] {
        Array((remoteContext?.scienceArticles ?? []).prefix(3))
    }

    @ViewBuilder
    private var scienceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("个性化科学期刊", "Personalized science journals", language: language))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                    Text(L10n.text("至少三篇，持续可刷新。", "At least three items and always refreshable.", language: language))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                }

                Spacer()

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .soft)
                    impact.impactOccurred()
                    Task {
                        await syncCoordinator.refreshEnrichment(
                            context: modelContext,
                            language: language,
                            force: true,
                            trigger: "home_science_refresh"
                        )
                    }
                } label: {
                    Label(L10n.text("刷新", "Refresh", language: language), systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(A10Palette.brand)
            }

            A10ScienceRecommendationSection(
                articles: currentScienceArticles,
                language: language
            )
            if currentScienceArticles.isEmpty {
                A10Card {
                    Text(
                        syncCoordinator.isEnrichmentSyncing
                        ? L10n.text("核心状态已经回来了，科学期刊还在做个性化富化。稍等一下，或者点刷新继续拉取至少三篇高匹配内容。", "Core state is already back. Science journals are still being personalized. Wait a moment or refresh to keep pulling at least three high-match papers.", language: language)
                        : L10n.text("科学期刊正在整理中，点刷新会继续拉取至少三篇与你当前状态匹配的内容。", "Science journals are still being prepared. Tap refresh to keep fetching at least three items matched to your current state.", language: language)
                    )
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bayesianInsightModel(snapshot: A10LoopSnapshot) -> A10BayesianInsight? {
        guard remoteContext != nil else { return nil }

        let stressScore = remoteContext?.effectiveStressScore ?? snapshot.stressScore
        let readiness = remoteContext?.readinessScore ?? max(32, 100 - stressScore * 7)
        let sleepHours = remoteContext?.dashboard?.todayLog?.sleep_duration_minutes.map { Double($0) / 60.0 } ?? 0
        let priorBase = Double(readiness) - Double(stressScore * 3) + (sleepHours >= 6.5 ? 6 : -4)
        let prior = min(max(priorBase, 18), 92)
        let hrv = remoteContext?.dashboard?.hardwareData?.hrv?.value
        let likelihood = BayesianEngine.calculateLikelihood(
            hrvData: BayesianHRVData(rmssd: hrv, lf_hf_ratio: nil)
        )
        let evidenceWeight = BayesianEngine.calculateEvidenceWeight(
            papers: (remoteContext?.scienceArticles ?? []).prefix(5).map { article in
                BayesianPaper(
                    id: article.id,
                    title: article.title,
                    relevanceScore: Double(article.matchPercentage ?? 55) / 100.0,
                    url: article.sourceUrl
                )
            }
        )
        let posterior = BayesianEngine.calculateBayesianPosterior(
            prior: prior,
            likelihood: likelihood,
            evidence: evidenceWeight
        )
        let primaryAction = remoteContext?.proactiveBrief?.microAction
            ?? remoteContext?.recommendations.first?.action
            ?? snapshot.nextActionTitle

        let headline: String
        if posterior >= 72 {
            headline = L10n.text("当前先验支持先做恢复动作，你很可能会在小动作后明显降焦虑。", "Current priors support a recovery-first move; a small action is likely to reduce anxiety noticeably.", language: language)
        } else if posterior >= 56 {
            headline = L10n.text("当前判断偏向先稳住身体，再继续补证据。", "Current judgment leans toward stabilizing the body first, then gathering more evidence.", language: language)
        } else {
            headline = L10n.text("当前先验还不够稳，先补状态信号再判断会更准。", "The current prior is still weak. Add more state signals before deciding.", language: language)
        }

        let detail = L10n.text(
            "先验 \(Int(prior.rounded())) · 身体似然 \(Int(likelihood.rounded())) · 证据权重 \(Int(evidenceWeight.rounded()))。当前最优策略不是多想，而是先降低唤醒。",
            "Prior \(Int(prior.rounded())) · body likelihood \(Int(likelihood.rounded())) · evidence weight \(Int(evidenceWeight.rounded())). The best next move is not more thinking, but lowering arousal first.",
            language: language
        )

        return A10BayesianInsight(
            headline: headline,
            detail: detail,
            action: primaryAction,
            posterior: Int(posterior.rounded())
        )
    }

    private func homeProgressItems(snapshot: A10LoopSnapshot) -> [A10HomeProgressItem] {
        [
            inquiryProgressItem(snapshot: snapshot),
            recordProgressItem(snapshot: snapshot),
            analysisProgressItem(snapshot: snapshot),
            actionProgressItem(snapshot: snapshot)
        ]
    }

    private func inquiryProgressItem(snapshot: A10LoopSnapshot) -> A10HomeProgressItem {
        if let inquiry = remoteContext?.pendingInquiry {
            return A10HomeProgressItem(
                stage: .inquiry,
                progress: 42,
                statusText: L10n.text("待回答", "Pending", language: language),
                summary: inquiry.questionText,
                detail: inquiry.feedContent?.title ?? L10n.text("回答这一个问题后，Max 才能继续往下收窄。", "Answer this question and Max can narrow the next step.", language: language),
                tint: A10Palette.warning,
                ctaTitle: L10n.text("去和 Max 聊", "Open Max", language: language),
                action: .openMax(intent: "inquiry", question: nil)
            )
        }

        let detail = remoteContext?.focusText ?? L10n.text("Max 已拿到今天的重点。", "Max already has today's main focus.", language: language)
        return A10HomeProgressItem(
            stage: .inquiry,
            progress: stageRank(snapshot.stage) > stageRank(.inquiry) || remoteContext != nil ? 100 : 18,
            statusText: L10n.text("已准备", "Ready", language: language),
            summary: L10n.text("今天先聊什么，已经整理好了。", "Today's opening direction is already prepared.", language: language),
            detail: detail,
            tint: A10Palette.success,
            ctaTitle: L10n.text("让 Max 继续问", "Let Max continue", language: language),
            action: .openMax(intent: "inquiry", question: nil)
        )
    }

    private func recordProgressItem(snapshot: A10LoopSnapshot) -> A10HomeProgressItem {
        let signalCount = remoteContext?.signalCount ?? 0
        let progress = remoteContext?.hasSignals == true
            ? min(max(signalCount * 12, 28), 100)
            : (stageRank(snapshot.stage) > stageRank(.calibration) ? 100 : 12)

        let summary = remoteContext?.hasSignals == true
            ? L10n.text("今天的身体和状态信息已经有一部分了。", "Some of today's body and state details are already in.", language: language)
            : L10n.text("今天还缺少状态记录。", "Today's state note is still missing.", language: language)

        let detail = remoteContext?.hasSignals == true
            ? L10n.text("已拿到 \(signalCount) 项有效信号。", "Already collected \(signalCount) useful signals.", language: language)
            : L10n.text("先补一条最简单的记录，后面的建议会更贴近你。", "Add one simple note first and the next guidance will fit better.", language: language)

        return A10HomeProgressItem(
            stage: .calibration,
            progress: progress,
            statusText: remoteContext?.hasSignals == true ? L10n.text("已记录", "Recorded", language: language) : L10n.text("待补充", "Needed", language: language),
            summary: summary,
            detail: detail,
            tint: remoteContext?.hasSignals == true ? A10Palette.info : A10Palette.warning,
            ctaTitle: remoteContext?.hasSignals == true ? L10n.text("继续补充", "Add more", language: language) : L10n.text("开始记录", "Start note", language: language),
            action: .startCalibration
        )
    }

    private func analysisProgressItem(snapshot: A10LoopSnapshot) -> A10HomeProgressItem {
        if let brief = remoteContext?.proactiveBrief {
            return A10HomeProgressItem(
                stage: .evidence,
                progress: 100,
                statusText: L10n.text("已整理", "Ready", language: language),
                summary: brief.title,
                detail: brief.understanding,
                tint: A10Palette.brand,
                ctaTitle: L10n.text("让 Max 讲清楚", "Let Max explain", language: language),
                action: .openMax(intent: "proactive_brief", question: nil)
            )
        }

        let baseProgress = remoteContext?.hasSignals == true ? 58 : (stageRank(snapshot.stage) > stageRank(.evidence) ? 100 : 20)
        return A10HomeProgressItem(
            stage: .evidence,
            progress: baseProgress,
            statusText: remoteContext?.hasSignals == true ? L10n.text("整理中", "Preparing", language: language) : L10n.text("等待中", "Waiting", language: language),
            summary: remoteContext?.hasSignals == true
                ? L10n.text("原因和建议正在靠近你的真实状态。", "Reasons and guidance are being tailored to your real state.", language: language)
                : L10n.text("还缺少今天的状态，暂时讲不清原因。", "Today's state is still missing, so the reason isn't clear yet.", language: language),
            detail: remoteContext?.hasSignals == true
                ? L10n.text("再多一点信息，Max 就能把原因讲得更准确。", "A bit more signal and Max can explain more precisely.", language: language)
                : L10n.text("先记录，再让 Max 帮你分析。", "Record first, then let Max help analyze.", language: language),
            tint: A10Palette.brandSecondary,
            ctaTitle: remoteContext?.hasSignals == true ? L10n.text("去问 Max", "Ask Max", language: language) : L10n.text("先去记录", "Record first", language: language),
            action: remoteContext?.hasSignals == true ? .openMax(intent: "evidence_explain", question: nil) : .startCalibration
        )
    }

    private func actionProgressItem(snapshot: A10LoopSnapshot) -> A10HomeProgressItem {
        if let activePlan = remoteContext?.activePlan, remoteContext?.hasActivePlan == true {
            return A10HomeProgressItem(
                stage: .action,
                progress: max(8, min(activePlan.progress, 100)),
                statusText: L10n.text("进行中", "In progress", language: language),
                summary: activePlan.title,
                detail: L10n.text("已经推进到 \(activePlan.progress)% 了，剩下的交给 Max 帮你收窄。", "You're already \(activePlan.progress)% through it. Let Max narrow the rest.", language: language),
                tint: A10Palette.success,
                ctaTitle: L10n.text("让 Max 接手", "Let Max take over", language: language),
                action: .openMax(intent: "plan_review", question: nil)
            )
        }

        let total = max((remoteContext?.openHabitsCount ?? 0) + (remoteContext?.completedHabitsCount ?? 0), max(activePlansCount + completedPlansCount, 1))
        let completed = max(remoteContext?.completedHabitsCount ?? 0, completedPlansCount)
        let progress = Int((Double(completed) / Double(total)) * 100)

        return A10HomeProgressItem(
            stage: .action,
            progress: progress,
            statusText: progress > 0 ? L10n.text("已开始", "Started", language: language) : L10n.text("待开始", "Not started", language: language),
            summary: progress > 0
                ? L10n.text("今天已经开始推进。", "Today's plan has already started moving.", language: language)
                : L10n.text("今天还没有开始动作。", "No action has started yet today.", language: language),
            detail: progress > 0
                ? L10n.text("如果不想自己判断下一步，可以直接交给 Max。", "If you don't want to decide the next step yourself, hand it to Max.", language: language)
                : L10n.text("Max 可以根据你的近况，先帮你压成一个最轻的动作。", "Max can compress the next step into one light action.", language: language),
            tint: progress > 0 ? A10Palette.success : A10Palette.info,
            ctaTitle: L10n.text("让 Max 安排", "Let Max plan it", language: language),
            action: .openMax(intent: progress > 0 ? "plan_review" : "proactive_brief", question: nil)
        )
    }

    private func performProgressAction(_ item: A10HomeProgressItem) {
        switch item.action {
        case .openMax(let intent, let question):
            openMaxFromHero(intent: intent, question: question)
        case .startCalibration:
            triggerMaxExecutionFromHero(.startCalibration)
        case .startBreathing(let minutes):
            triggerMaxExecutionFromHero(.startBreathing, userInfo: ["duration": minutes])
        }
    }

    private func stageRank(_ stage: A10LoopStage) -> Int {
        switch stage {
        case .inquiry: return 0
        case .calibration: return 1
        case .evidence: return 2
        case .action: return 3
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
    @State private var selectedEmotionShortcut: A10EmotionShortcut?
    @State private var shortcutSheetModels: [String: A10EmotionShortcutSheetModel] = [:]
    @State private var shortcutSheetLoadingIDs: Set<String> = []
    @State private var selectedShortcutDetent: PresentationDetent = .large

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
                    eyebrow: L10n.text("系统状态", "System status", language: language),
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
        .sheet(item: $selectedEmotionShortcut) { shortcut in
            A10EmotionShortcutSheet(
                shortcut: shortcut,
                model: shortcutSheetModel(for: shortcut),
                isLoading: shortcutSheetLoadingIDs.contains(shortcut.id),
                language: language
            )
            .presentationDetents([.medium, .large], selection: $selectedShortcutDetent)
            .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugOpenA10Shortcut)) { notification in
            guard let shortcutID = (notification.userInfo?["shortcutID"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  let shortcut = emotionWheelModel.shortcuts.first(where: { $0.id == shortcutID }) else {
                return
            }
            handleEmotionShortcut(shortcut)
        }
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
        if syncCoordinator.isCoreSyncing {
            return L10n.text(
                "同步偏好与核心系统状态",
                "Syncing preferences and core system state",
                language: language
            )
        }

        if syncCoordinator.isEnrichmentSyncing && remoteContext != nil {
            return L10n.text(
                "核心状态已就绪，正在补充解释和期刊匹配",
                "Core state is ready while explanations and journal matching are still loading.",
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
        if syncCoordinator.isCoreSyncing {
            return L10n.text("同步中", "Syncing", language: language)
        }

        if syncCoordinator.isEnrichmentSyncing {
            return L10n.text("补充中", "Enriching", language: language)
        }

        if remoteContext != nil {
            return L10n.text("已就绪", "Ready", language: language)
        }

        return L10n.text("初始化", "Booting", language: language)
    }

    private var meHeaderBadgeTint: Color {
        if syncCoordinator.isCoreSyncing {
            return A10Palette.info
        }

        if syncCoordinator.isEnrichmentSyncing {
            return A10Palette.brandSecondary
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
        selectedShortcutDetent = .large
        selectedEmotionShortcut = shortcut
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        UISelectionFeedbackGenerator().selectionChanged()
        loadEmotionShortcutSheet(shortcut)

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

        if shortcut.id == "signal" {
            Task {
                await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "me_shortcut_signal")
            }
        }
    }

    private func shortcutSheetModel(for shortcut: A10EmotionShortcut) -> A10EmotionShortcutSheetModel {
        shortcutSheetModels[shortcut.id] ?? placeholderShortcutSheetModel(for: shortcut)
    }

    private func placeholderShortcutSheetModel(for shortcut: A10EmotionShortcut) -> A10EmotionShortcutSheetModel {
        let badges: [A10EmotionShortcutBadge]
        switch shortcut.id {
        case "state":
            badges = [
                A10EmotionShortcutBadge(title: L10n.text("7天睡眠", "7d sleep", language: language), value: sleepAverageText, tint: A10Palette.info),
                A10EmotionShortcutBadge(title: L10n.text("7天压力", "7d stress", language: language), value: stressAverageText, tint: A10Palette.warning),
                A10EmotionShortcutBadge(title: L10n.text("就绪度", "Readiness", language: language), value: readinessText, tint: A10Palette.success)
            ]
        case "plan":
            badges = [
                A10EmotionShortcutBadge(title: L10n.text("进行中", "Active", language: language), value: "\(plans.filter { !$0.isCompleted }.count)", tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: L10n.text("完成率", "Completion", language: language), value: completionRateText, tint: A10Palette.success),
                A10EmotionShortcutBadge(title: L10n.text("主计划", "Lead plan", language: language), value: planProgressText, tint: A10Palette.info)
            ]
        case "signal":
            badges = [
                A10EmotionShortcutBadge(title: "HRV", value: hrvText, tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: "RHR", value: rhrText, tint: A10Palette.warning),
                A10EmotionShortcutBadge(title: L10n.text("步数", "Steps", language: language), value: stepsText, tint: A10Palette.success)
            ]
        case "focus":
            badges = [
                A10EmotionShortcutBadge(title: L10n.text("当前焦点", "Current focus", language: language), value: remoteContext?.focusText ?? "—", tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: L10n.text("待补变量", "Open gaps", language: language), value: "\(remoteContext?.pendingInquiry == nil ? 0 : 1)", tint: A10Palette.warning),
                A10EmotionShortcutBadge(title: L10n.text("主导阶段", "Lead stage", language: language), value: currentSnapshot?.stage.title(language: language) ?? "A10", tint: A10Palette.info)
            ]
        case "max":
            badges = [
                A10EmotionShortcutBadge(title: L10n.text("最近状态", "Latest state", language: language), value: remoteContext?.proactiveBrief == nil ? L10n.text("待命", "Ready", language: language) : L10n.text("已理解", "Context built", language: language), tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: L10n.text("进行中计划", "Active plans", language: language), value: "\(plans.filter { !$0.isCompleted }.count)", tint: A10Palette.success),
                A10EmotionShortcutBadge(title: L10n.text("待答问题", "Pending Q", language: language), value: "\(remoteContext?.pendingInquiry == nil ? 0 : 1)", tint: A10Palette.warning)
            ]
        default:
            badges = [
                A10EmotionShortcutBadge(title: L10n.text("状态", "Status", language: language), value: L10n.text("已记录", "Tracked", language: language), tint: A10Palette.info)
            ]
        }

        return A10EmotionShortcutSheetModel(
            title: shortcut.title.resolve(language),
            summary: L10n.text("正在汇总真实统计，而不是只给说明文案。", "Loading actual stats instead of a generic explanation.", language: language),
            badges: badges,
            sections: [
                A10EmotionShortcutSection(
                    title: L10n.text("统计视图", "Stats view", language: language),
                    rows: [
                        A10EmotionShortcutRow(
                            label: L10n.text("状态", "Status", language: language),
                            value: L10n.text("准备中", "Preparing", language: language)
                        )
                    ]
                )
            ]
        )
    }

    private func loadEmotionShortcutSheet(_ shortcut: A10EmotionShortcut) {
        shortcutSheetLoadingIDs.insert(shortcut.id)

        Task {
            let model = await buildEmotionShortcutSheetModel(for: shortcut)
            await MainActor.run {
                shortcutSheetModels[shortcut.id] = model
                shortcutSheetLoadingIDs.remove(shortcut.id)
            }
        }
    }

    private func buildEmotionShortcutSheetModel(for shortcut: A10EmotionShortcut) async -> A10EmotionShortcutSheetModel {
        switch shortcut.id {
        case "state":
            return await buildStateShortcutSheetModel()
        case "plan":
            return buildPlanShortcutSheetModel()
        case "signal":
            return await buildSignalShortcutSheetModel()
        case "focus":
            return await buildFocusShortcutSheetModel()
        case "max":
            return await buildMaxShortcutSheetModel()
        default:
            return placeholderShortcutSheetModel(for: shortcut)
        }
    }

    private func buildStateShortcutSheetModel() async -> A10EmotionShortcutSheetModel {
        let analysisHistory = (try? await supabase.getAnalysisHistory(limit: 6)) ?? []
        let weeklyLogs = remoteContext?.dashboard?.weeklyLogs ?? []
        let todayLog = remoteContext?.dashboard?.todayLog
        let summary = remoteContext?.dashboard?.todayLog?.ai_recommendation
            ?? currentSnapshot?.summary
            ?? L10n.text("系统还在补状态。", "The system is still filling in state data.", language: language)

        return A10EmotionShortcutSheetModel(
            title: L10n.text("状态", "State", language: language),
            summary: summary,
            badges: [
                A10EmotionShortcutBadge(title: L10n.text("7天睡眠", "7d sleep", language: language), value: sleepAverageText, tint: A10Palette.info),
                A10EmotionShortcutBadge(title: L10n.text("7天压力", "7d stress", language: language), value: stressAverageText, tint: A10Palette.warning),
                A10EmotionShortcutBadge(title: L10n.text("就绪度", "Readiness", language: language), value: readinessText, tint: A10Palette.success)
            ],
            sections: [
                A10EmotionShortcutSection(
                    title: L10n.text("今日状态", "Today", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("压力", "Stress", language: language), value: metricValue(todayLog?.stress_level, suffix: "/10")),
                        A10EmotionShortcutRow(label: L10n.text("焦虑", "Anxiety", language: language), value: metricValue(todayLog?.anxiety_level, suffix: "/10")),
                        A10EmotionShortcutRow(label: L10n.text("精力", "Energy", language: language), value: metricValue(todayLog?.energy_level ?? todayLog?.morning_energy, suffix: "/10")),
                        A10EmotionShortcutRow(label: L10n.text("清晰度", "Clarity", language: language), value: metricValue(todayLog?.mental_clarity, suffix: "/10"))
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("近7天趋势", "Last 7 days", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("平均睡眠", "Average sleep", language: language), value: sleepAverageText),
                        A10EmotionShortcutRow(label: L10n.text("平均压力", "Average stress", language: language), value: stressAverageText),
                        A10EmotionShortcutRow(label: L10n.text("记录天数", "Logged days", language: language), value: "\(weeklyLogs.count)")
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("系统判断", "System view", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("最新分析", "Latest analysis", language: language), value: analysisHistory.first?.statusText ?? L10n.text("暂无", "None", language: language)),
                        A10EmotionShortcutRow(label: L10n.text("置信度", "Confidence", language: language), value: analysisHistory.first?.confidenceText ?? "—"),
                        A10EmotionShortcutRow(label: L10n.text("更新时间", "Updated", language: language), value: analysisHistory.first?.createdAt ?? formattedDate(remoteContext?.refreshedAt))
                    ]
                )
            ]
        )
    }

    private func buildPlanShortcutSheetModel() -> A10EmotionShortcutSheetModel {
        let activePlans = plans.filter { !$0.isCompleted }
        let completedPlans = plans.filter(\.isCompleted)
        let totalPlans = max(plans.count, 1)
        let completionRate = Int(round(Double(completedPlans.count) / Double(totalPlans) * 100))
        let avgMinutes = plans.isEmpty ? 0 : Int(round(Double(plans.map(\.estimatedMinutes).reduce(0, +)) / Double(plans.count)))
        let activePlanTitle = remoteContext?.activePlan?.title
            ?? activePlans.first?.title
            ?? L10n.text("今天还没有在执行的计划。", "There is no active plan right now.", language: language)

        return A10EmotionShortcutSheetModel(
            title: L10n.text("计划", "Plans", language: language),
            summary: activePlanTitle,
            badges: [
                A10EmotionShortcutBadge(title: L10n.text("进行中", "Active", language: language), value: "\(activePlans.count)", tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: L10n.text("完成率", "Completion", language: language), value: "\(completionRate)%", tint: A10Palette.success),
                A10EmotionShortcutBadge(title: L10n.text("平均时长", "Avg time", language: language), value: avgMinutes > 0 ? "\(avgMinutes)m" : "—", tint: A10Palette.info)
            ],
            sections: [
                A10EmotionShortcutSection(
                    title: L10n.text("执行统计", "Execution", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("主计划", "Lead plan", language: language), value: activePlanTitle),
                        A10EmotionShortcutRow(label: L10n.text("远端进度", "Remote progress", language: language), value: planProgressText),
                        A10EmotionShortcutRow(label: L10n.text("已完成", "Completed", language: language), value: "\(completedPlans.count)")
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("阻力点", "Friction", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("当前掉队点", "Current drop-off", language: language), value: activePlans.first?.detail ?? L10n.text("当前没有明显掉队点。", "No clear drop-off point right now.", language: language)),
                        A10EmotionShortcutRow(label: L10n.text("未完成项", "Open items", language: language), value: "\(activePlans.count)")
                    ]
                )
            ]
        )
    }

    private func buildSignalShortcutSheetModel() async -> A10EmotionShortcutSheetModel {
        let historyRows = await loadHealthMetricRows(limit: 160)
        let grouped = Dictionary(grouping: historyRows, by: \.data_type)

        return A10EmotionShortcutSheetModel(
            title: L10n.text("信号", "Signals", language: language),
            summary: remoteContext?.hasSignals == true
                ? L10n.text("穿戴和主观状态信号已经接入。", "Wearable and subjective signals are connected.", language: language)
                : L10n.text("目前信号还不够密。", "Signals are still sparse.", language: language),
            badges: [
                A10EmotionShortcutBadge(title: "HRV", value: hrvText, tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: "RHR", value: rhrText, tint: A10Palette.warning),
                A10EmotionShortcutBadge(title: L10n.text("步数", "Steps", language: language), value: stepsText, tint: A10Palette.success)
            ],
            sections: [
                A10EmotionShortcutSection(
                    title: L10n.text("当前硬件", "Current hardware", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: "HRV", value: hrvText),
                        A10EmotionShortcutRow(label: "RHR", value: rhrText),
                        A10EmotionShortcutRow(label: L10n.text("睡眠分", "Sleep score", language: language), value: sleepScoreText),
                        A10EmotionShortcutRow(label: L10n.text("步数", "Steps", language: language), value: stepsText)
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("近30天均值", "30d averages", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: "HRV", value: metricValue(averageMetric(grouped["hrv"]).map { Int($0.rounded()) })),
                        A10EmotionShortcutRow(label: "RHR", value: metricValue(averageMetric(grouped["resting_heart_rate"]).map { Int($0.rounded()) })),
                        A10EmotionShortcutRow(label: L10n.text("步数", "Steps", language: language), value: metricValue(averageMetric(grouped["steps"]).map { Int($0.rounded()) })),
                        A10EmotionShortcutRow(label: L10n.text("睡眠分", "Sleep score", language: language), value: metricValue(averageMetric(grouped["sleep_score"]).map { Int($0.rounded()) }))
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("联动状态", "Coupled state", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("7天睡眠", "7d sleep", language: language), value: sleepAverageText),
                        A10EmotionShortcutRow(label: L10n.text("7天压力", "7d stress", language: language), value: stressAverageText),
                        A10EmotionShortcutRow(label: L10n.text("有效信号数", "Signal count", language: language), value: "\(remoteContext?.signalCount ?? 0)")
                    ]
                )
            ]
        )
    }

    private func buildFocusShortcutSheetModel() async -> A10EmotionShortcutSheetModel {
        let inquiryRows = await loadInquiryHistoryRows(limit: 12)
        let inquirySummary = (try? await supabase.getInquiryContextSummary(language: language.apiCode, limit: 8))
            ?? L10n.text("还没有足够的问询上下文。", "There is not enough inquiry context yet.", language: language)
        let topTopic = Dictionary(grouping: inquiryRows.compactMap(\.question_type), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
            .first?.key ?? L10n.text("未形成", "Not formed", language: language)
        let topGap = inquiryRows
            .flatMap { $0.data_gaps_addressed ?? [] }
            .reduce(into: [String: Int]()) { result, gap in
                result[gap, default: 0] += 1
            }
            .sorted { $0.value > $1.value }
            .first?.key ?? L10n.text("暂无", "None", language: language)

        return A10EmotionShortcutSheetModel(
            title: L10n.text("聚焦", "Focus", language: language),
            summary: remoteContext?.focusText
                ?? L10n.text("当前没有显式聚焦，系统还在压缩主要变量。", "There is no explicit focus yet, so the system is still compressing the key variable.", language: language),
            badges: [
                A10EmotionShortcutBadge(title: L10n.text("当前焦点", "Current focus", language: language), value: remoteContext?.focusText ?? "—", tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: L10n.text("高频主题", "Top theme", language: language), value: topTopic, tint: A10Palette.info),
                A10EmotionShortcutBadge(title: L10n.text("主缺口", "Top gap", language: language), value: topGap, tint: A10Palette.warning)
            ],
            sections: [
                A10EmotionShortcutSection(
                    title: L10n.text("当前聚焦", "Current focus", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("系统焦点", "System focus", language: language), value: remoteContext?.focusText ?? "—"),
                        A10EmotionShortcutRow(label: L10n.text("待答问题", "Pending question", language: language), value: remoteContext?.pendingInquiry?.questionText ?? L10n.text("暂无", "None", language: language))
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("近7天高频触发", "Recent frequent triggers", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("高频主题", "Top theme", language: language), value: topTopic),
                        A10EmotionShortcutRow(label: L10n.text("主数据缺口", "Primary data gap", language: language), value: topGap)
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("问询总结", "Inquiry summary", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("上下文", "Context", language: language), value: inquirySummary)
                    ]
                )
            ]
        )
    }

    private func buildMaxShortcutSheetModel() async -> A10EmotionShortcutSheetModel {
        let conversations = await loadConversationRows(limit: 120)
        let analysisHistory = (try? await supabase.getAnalysisHistory(limit: 10)) ?? []
        let userMessages = conversations.filter { ($0.role ?? "") == "user" }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        let recentSevenDays = userMessages.filter {
            guard let created = parseISODate($0.created_at) else { return false }
            return created >= sevenDaysAgo
        }
        let topicCounts = inferConversationTopics(from: userMessages)

        return A10EmotionShortcutSheetModel(
            title: "Max",
            summary: remoteContext?.proactiveBrief?.title
                ?? L10n.text("Max 已经待命，但这里只展示工作统计。", "Max is ready; this surface now shows operational stats only.", language: language),
            badges: [
                A10EmotionShortcutBadge(title: L10n.text("7天对话", "7d chats", language: language), value: "\(recentSevenDays.count)", tint: A10Palette.brand),
                A10EmotionShortcutBadge(title: L10n.text("主主题", "Top theme", language: language), value: topicCounts.sorted { $0.value > $1.value }.first?.key ?? L10n.text("未形成", "Not formed", language: language), tint: A10Palette.info),
                A10EmotionShortcutBadge(title: L10n.text("已落地动作", "Landed actions", language: language), value: "\(plans.filter(\.isCompleted).count)", tint: A10Palette.success)
            ],
            sections: [
                A10EmotionShortcutSection(
                    title: L10n.text("近7/30天使用", "7d / 30d usage", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("7天用户消息", "7d user turns", language: language), value: "\(recentSevenDays.count)"),
                        A10EmotionShortcutRow(label: L10n.text("30天消息总数", "30d total turns", language: language), value: "\(userMessages.count)"),
                        A10EmotionShortcutRow(label: L10n.text("最近一次交互", "Last interaction", language: language), value: formattedDate(parseISODate(conversations.first?.created_at)))
                    ]
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("主题分布", "Topic distribution", language: language),
                    rows: topicCounts
                        .sorted { $0.value > $1.value }
                        .prefix(3)
                        .map { A10EmotionShortcutRow(label: $0.key, value: "\($0.value)") }
                ),
                A10EmotionShortcutSection(
                    title: L10n.text("分析联动", "Analysis linkage", language: language),
                    rows: [
                        A10EmotionShortcutRow(label: L10n.text("最近分析状态", "Latest analysis state", language: language), value: analysisHistory.first?.statusText ?? L10n.text("暂无", "None", language: language)),
                        A10EmotionShortcutRow(label: L10n.text("最近置信度", "Latest confidence", language: language), value: analysisHistory.first?.confidenceText ?? "—"),
                        A10EmotionShortcutRow(label: L10n.text("待答问题", "Pending question", language: language), value: "\(remoteContext?.pendingInquiry == nil ? 0 : 1)")
                    ]
                )
            ]
        )
    }

    private func loadHealthMetricRows(limit: Int) async -> [A10HealthMetricRow] {
        guard let user = supabase.currentUser else { return [] }
        let endpoint = "user_health_data?user_id=eq.\(user.id)&select=data_type,value,recorded_at&order=recorded_at.desc&limit=\(max(20, limit))"
        return (try? await supabase.request(endpoint)) ?? []
    }

    private func loadInquiryHistoryRows(limit: Int) async -> [A10InquirySheetRow] {
        guard let user = supabase.currentUser else { return [] }
        let endpoint = "inquiry_history?user_id=eq.\(user.id)&select=question_type,data_gaps_addressed,user_response,created_at,responded_at&order=created_at.desc&limit=\(max(4, limit))"
        return (try? await supabase.request(endpoint)) ?? []
    }

    private func loadConversationRows(limit: Int) async -> [A10ConversationSheetRow] {
        guard let user = supabase.currentUser else { return [] }
        let endpoint = "chat_conversations?user_id=eq.\(user.id)&select=role,content,created_at&order=created_at.desc&limit=\(max(20, limit))"
        return (try? await supabase.request(endpoint)) ?? []
    }

    private func averageMetric(_ rows: [A10HealthMetricRow]?) -> Double? {
        guard let rows, !rows.isEmpty else { return nil }
        let values = rows.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func inferConversationTopics(from rows: [A10ConversationSheetRow]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in rows {
            let content = (row.content ?? "").lowercased()
            if content.contains("sleep") || content.contains("睡眠") || content.contains("失眠") {
                counts[L10n.text("睡眠", "Sleep", language: language), default: 0] += 1
            }
            if content.contains("stress") || content.contains("压力") || content.contains("焦虑") || content.contains("anxiety") {
                counts[L10n.text("压力/焦虑", "Stress / anxiety", language: language), default: 0] += 1
            }
            if content.contains("energy") || content.contains("能量") || content.contains("疲劳") {
                counts[L10n.text("能量", "Energy", language: language), default: 0] += 1
            }
            if content.contains("exercise") || content.contains("运动") || content.contains("锻炼") {
                counts[L10n.text("运动", "Exercise", language: language), default: 0] += 1
            }
        }
        return counts
    }

    private func metricValue(_ value: Int?, suffix: String = "") -> String {
        guard let value else { return "—" }
        return "\(value)\(suffix)"
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func parseISODate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    private var sleepAverageText: String {
        let hours = remoteContext?.dashboard?.averageSleepHours ?? 0
        guard hours > 0 else { return "—" }
        return String(format: "%.1fh", hours)
    }

    private var stressAverageText: String {
        let stress = remoteContext?.dashboard?.averageStress ?? 0
        guard stress > 0 else { return "—" }
        return String(format: "%.1f/10", stress)
    }

    private var readinessText: String {
        guard let readiness = remoteContext?.readinessScore else { return "—" }
        return "\(readiness)"
    }

    private var completionRateText: String {
        guard !plans.isEmpty else { return "0%" }
        let completed = plans.filter(\.isCompleted).count
        return "\(Int(round(Double(completed) / Double(plans.count) * 100)))%"
    }

    private var planProgressText: String {
        if let activePlan = remoteContext?.activePlan {
            return "\(activePlan.progress)%"
        }
        return plans.first(where: { !$0.isCompleted }) == nil ? "—" : "0%"
    }

    private var hrvText: String {
        guard let hrv = remoteContext?.dashboard?.hardwareData?.hrv?.value else { return "—" }
        return "\(Int(hrv.rounded()))"
    }

    private var rhrText: String {
        guard let rhr = remoteContext?.dashboard?.hardwareData?.resting_heart_rate?.value else { return "—" }
        return "\(Int(rhr.rounded()))"
    }

    private var sleepScoreText: String {
        guard let score = remoteContext?.dashboard?.hardwareData?.sleep_score?.value else { return "—" }
        return "\(Int(score.rounded()))"
    }

    private var stepsText: String {
        guard let steps = remoteContext?.dashboard?.hardwareData?.steps?.value else { return "—" }
        return "\(Int(steps.rounded()))"
    }

    private struct A10HealthMetricRow: Decodable {
        let data_type: String
        let value: Double
        let recorded_at: String?
    }

    private struct A10InquirySheetRow: Decodable {
        let question_type: String?
        let data_gaps_addressed: [String]?
        let user_response: String?
        let created_at: String?
        let responded_at: String?
    }

    private struct A10ConversationSheetRow: Decodable {
        let role: String?
        let content: String?
        let created_at: String?
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
        max(metrics.safeAreaInsets.top - 35, 4)
    }

    private var mistHeight: CGFloat {
        max(metrics.safeAreaInsets.top + 39, 69)
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("今日总览", "Today's overview", language: language))
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

private enum A10HomeProgressAction {
    case openMax(intent: String?, question: String?)
    case startCalibration
    case startBreathing(minutes: Int)
}

private struct A10HomeProgressItem: Identifiable {
    let stage: A10LoopStage
    let progress: Int
    let statusText: String
    let summary: String
    let detail: String
    let tint: Color
    let ctaTitle: String
    let action: A10HomeProgressAction

    var id: String { stage.rawValue }
}

private struct A10HomeProgressRow: View {
    let item: A10HomeProgressItem
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(item.tint.opacity(0.14))
                        .frame(width: 38, height: 38)

                    Image(systemName: item.stage.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.stage.title(language: language))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.ink)

                        Text(item.statusText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(item.tint)
                    }

                    Text(item.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.detail)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(item.progress)%")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(A10Palette.inkSecondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(A10Palette.inset.opacity(0.7))
                    Capsule()
                        .fill(item.tint)
                        .frame(width: max(18, proxy.size.width * CGFloat(item.progress) / 100))
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(A10Palette.inset.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.tint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct A10HomeProgressSheet: View {
    let item: A10HomeProgressItem
    let language: AppLanguage
    let onPrimaryAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.stage.title(language: language))
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(A10Palette.ink)

                            Text(item.statusText + " · \(item.progress)%")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(item.tint)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(A10Palette.ink)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    A10Card(highlighted: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.summary)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(A10Palette.ink)

                            Text(item.detail)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(A10Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            onPrimaryAction()
                        }
                    } label: {
                        Text(item.ctaTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(A10PrimaryButtonStyle())

                    Text(
                        L10n.text(
                            "首页只保留判断和入口，真正的下一步交给 Max 来接手。",
                            "Home only keeps the judgment and the entry point. Let Max take over the actual next step.",
                            language: language
                        )
                    )
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
                }
                .padding(20)
            }
        }
    }
}

private struct A10BayesianInsight {
    let headline: String
    let detail: String
    let action: String
    let posterior: Int
}

private struct A10BayesianInsightCard: View {
    let insight: A10BayesianInsight
    let language: AppLanguage

    var body: some View {
        A10Card(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("降低焦虑后验", "Anxiety-lowering posterior", language: language))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text("\(insight.posterior)%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.brand)
                    }

                    Spacer()

                    Image(systemName: "waveform.path.ecg.text.page")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(A10Palette.brand)
                }

                Text(insight.headline)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "bolt.heart.fill")
                        .foregroundStyle(A10Palette.warning)
                    Text(insight.action)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(A10Palette.inset.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct A10ScienceRecommendationSection: View {
    let articles: [ScienceArticle]
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 10) {
            ForEach(articles) { article in
                A10ScienceArticleCard(article: article, language: language)
            }
        }
    }
}

private struct A10ScienceArticleCard: View {
    let article: ScienceArticle
    let language: AppLanguage

    private var localizedSummary: String {
        if language == .en {
            return article.summary ?? article.summaryZh ?? L10n.text("摘要待补充。", "Summary unavailable.", language: language)
        }
        return article.summaryZh ?? article.summary ?? L10n.text("摘要待补充。", "Summary unavailable.", language: language)
    }

    var body: some View {
        A10Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.titleZh ?? article.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(article.sourceType ?? L10n.text("科学来源", "Scientific source", language: language))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                    }

                    Spacer()

                    Text("\(article.matchPercentage ?? 0)%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(A10Palette.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(A10Palette.brand.opacity(0.12), in: Capsule())
                }

                Text(localizedSummary)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let breakdown = article.scoreBreakdown {
                    HStack(spacing: 8) {
                        A10ScienceBreakdownPill(title: L10n.text("历史", "History", language: language), value: breakdown.historyAlignment)
                        A10ScienceBreakdownPill(title: L10n.text("信号", "Signals", language: language), value: breakdown.signalAlignment)
                        A10ScienceBreakdownPill(title: L10n.text("主题", "Topic", language: language), value: breakdown.topicAlignment)
                    }
                }

                if let whyRecommended = A10NonEmpty(article.whyRecommended) {
                    Text(L10n.text("为什么推荐给你：", "Why this fits you: ", language: language) + whyRecommended)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let reasons = article.matchReasons, !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(reasons.prefix(3).enumerated()), id: \.offset) { item in
                            Text("• \(item.element)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(A10Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let actionableInsight = A10NonEmpty(article.actionableInsight) {
                    Text(L10n.text("可执行点：", "Actionable point: ", language: language) + actionableInsight)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let urlString = article.sourceUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(L10n.text("打开原文", "Open source", language: language), systemImage: "link")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(A10Palette.brand)
                }
            }
        }
    }
}

private struct A10ScienceBreakdownPill: View {
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text("\(value)")
                .fontWeight(.bold)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(A10Palette.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(A10Palette.inset.opacity(0.75), in: Capsule())
    }
}

private struct A10EmotionShortcutBadge: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let tint: Color
}

private struct A10EmotionShortcutRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private struct A10EmotionShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [A10EmotionShortcutRow]
}

private struct A10EmotionShortcutSheetModel {
    let title: String
    let summary: String
    let badges: [A10EmotionShortcutBadge]
    let sections: [A10EmotionShortcutSection]
}

private struct A10EmotionShortcutSheet: View {
    let shortcut: A10EmotionShortcut
    let model: A10EmotionShortcutSheetModel
    let isLoading: Bool
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss

    private var accentTint: Color {
        model.badges.first?.tint ?? A10Palette.brand
    }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(accentTint.opacity(0.16))
                                .frame(width: 52, height: 52)

                            Image(systemName: shortcut.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(accentTint)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.title)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(A10Palette.ink)

                            Text(L10n.text("健康统计概览", "Health stats overview", language: language))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(A10Palette.inkSecondary)
                        }

                        Spacer(minLength: 12)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(A10Palette.ink)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    A10Card(highlighted: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L10n.text("今日概览", "Today's overview", language: language))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(A10Palette.inkSecondary)
                                Spacer()
                                Text(shortcutSheetTimestamp)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(A10Palette.inkSecondary)
                            }

                            Text(model.summary)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(A10Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !model.badges.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("关键指标", "Key metrics", language: language))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(A10Palette.inkSecondary)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(model.badges) { badge in
                                    A10EmotionShortcutBadgeCard(badge: badge)
                                }
                            }
                        }
                    }

                    if isLoading {
                        A10Card(highlighted: true) {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(accentTint)
                                Text(L10n.text("正在刷新实时统计", "Refreshing live stats", language: language))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(A10Palette.inkSecondary)
                            }
                        }
                    }

                    ForEach(model.sections) { section in
                        A10Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(section.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(A10Palette.inkSecondary)

                                VStack(spacing: 0) {
                                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(row.label)
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .foregroundStyle(A10Palette.ink)
                                            Spacer(minLength: 12)
                                            Text(row.value)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(A10Palette.inkSecondary)
                                                .multilineTextAlignment(.trailing)
                                                .monospacedDigit()
                                        }
                                        .padding(.vertical, 10)

                                        if index < section.rows.count - 1 {
                                            Divider()
                                                .overlay(A10Palette.line.opacity(0.5))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
    }

    private var shortcutSheetTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = language == .en ? "MMM d, HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: Date())
    }
}

private struct A10EmotionShortcutBadgeCard: View {
    let badge: A10EmotionShortcutBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(badge.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
            Text(badge.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(badge.tint)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(A10Palette.inset.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(badge.tint.opacity(0.14), lineWidth: 1)
        )
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
