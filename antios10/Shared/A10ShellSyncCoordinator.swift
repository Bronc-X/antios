import Foundation
import SwiftData
import SwiftUI

@MainActor
final class A10ShellSyncCoordinator: ObservableObject {
    @Published private(set) var isCoreSyncing = false
    @Published private(set) var isEnrichmentSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastRemoteSource: String?
    @Published private(set) var remoteContext: A10ShellRemoteContext?

    private let supabase = SupabaseManager.shared
    private var syncGeneration = 0

    var isSyncing: Bool {
        isCoreSyncing || isEnrichmentSyncing
    }

    func sync(
        context: ModelContext,
        language: AppLanguage,
        force: Bool,
        trigger: String
    ) async {
        guard !isCoreSyncing else { return }
        syncGeneration += 1
        let generation = syncGeneration
        isCoreSyncing = true
        defer { isCoreSyncing = false }

        if force || lastSyncAt == nil {
            Task { [supabase] in
                await supabase.triggerDailyRecommendations(force: force, language: language.apiCode)
            }
        }

        async let dashboardTask: DashboardData? = loadOptional { [self] in
            try await self.supabase.getDashboardData()
        }
        async let recommendationsTask: [DailyAIRecommendationItem] = loadDefault([]) { [self] in
            try await self.supabase.getDailyRecommendations()
        }
        async let habitsTask: [SupabaseManager.HabitStatus] = loadDefault([]) { [self] in
            try await self.supabase.getHabitsForToday()
        }
        async let profileTask: ProfileSettings? = loadProfileSettings()
        async let inquiryTask: InquiryQuestion? = loadPendingInquiry(language: language)
        async let activePlanTask: A10ShellActivePlanSummary? = loadActivePlanSummary()

        let dashboard = await dashboardTask
        let recommendations = await recommendationsTask
        let habits = await habitsTask
        let profile = await profileTask
        let pendingInquiry = await inquiryTask
        let activePlan = await activePlanTask

        guard dashboard != nil
            || profile != nil
            || !recommendations.isEmpty
            || !habits.isEmpty
            || pendingInquiry != nil
            || activePlan != nil else {
            lastErrorMessage = "No usable remote data returned."
            return
        }

        do {
            try applyRemoteData(
                dashboard: dashboard,
                recommendations: recommendations,
                habits: habits,
                profile: profile,
                context: context,
                language: language
            )
            lastSyncAt = .now
            lastErrorMessage = nil
            lastRemoteSource = "dashboard"
            remoteContext = A10ShellRemoteContext(
                dashboard: dashboard,
                recommendations: recommendations,
                scienceArticles: remoteContext?.scienceArticles ?? [],
                habits: habits,
                profile: profile,
                pendingInquiry: pendingInquiry,
                proactiveBrief: remoteContext?.proactiveBrief,
                activePlan: activePlan,
                refreshedAt: .now
            )

            await supabase.captureUserSignal(
                domain: "a10_shell",
                action: "remote_hydrated",
                summary: "\(trigger): habits=\(habits.count), recommendations=\(recommendations.count), inquiry=\(pendingInquiry != nil)",
                metadata: [
                    "trigger": trigger,
                    "habits_count": habits.count,
                    "recommendations_count": recommendations.count,
                    "has_dashboard": dashboard != nil,
                    "has_profile": profile != nil,
                    "has_pending_inquiry": pendingInquiry != nil,
                    "has_active_plan": activePlan != nil
                ]
            )
            scheduleEnrichment(
                generation: generation,
                context: context,
                language: language,
                force: force,
                trigger: trigger,
                dashboard: dashboard,
                profile: profile
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshEnrichment(
        context: ModelContext,
        language: AppLanguage,
        force: Bool,
        trigger: String
    ) async {
        syncGeneration += 1
        let generation = syncGeneration
        await loadEnrichment(
            generation: generation,
            context: context,
            language: language,
            force: force,
            trigger: trigger,
            dashboard: remoteContext?.dashboard,
            profile: remoteContext?.profile
        )
    }

    func syncPlanToggle(_ plan: A10ActionPlan, context: ModelContext, language: AppLanguage) async {
        guard plan.source == .habit, let remoteID = nonEmpty(plan.remoteID) else { return }

        do {
            try await supabase.setHabitCompletion(habitId: remoteID, isCompleted: plan.isCompleted)
            lastSyncAt = .now
            lastErrorMessage = nil
            lastRemoteSource = "plans"
            await sync(context: context, language: language, force: false, trigger: "habit_toggle")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func syncPreferences(_ record: A10PreferenceRecord, language: AppLanguage) async {
        let reminders = ReminderPreferences(
            morning: record.notificationsEnabled,
            evening: record.notificationsEnabled,
            breathing: record.notificationsEnabled
        )

        do {
            _ = try await supabase.updateProfileSettings(
                ProfileSettingsUpdate(
                    preferred_language: language.apiCode,
                    reminder_preferences: reminders
                )
            )
            await supabase.captureUserSignal(
                domain: "a10_shell",
                action: "preferences_synced",
                summary: "notifications=\(record.notificationsEnabled), health_sync=\(record.healthSyncEnabled)",
                metadata: [
                    "language": language.rawValue,
                    "notifications_enabled": record.notificationsEnabled,
                    "health_sync_enabled": record.healthSyncEnabled,
                    "daily_check_in_hour": record.dailyCheckInHour
                ]
            )
            lastSyncAt = .now
            lastErrorMessage = nil
            lastRemoteSource = "profile"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func scheduleEnrichment(
        generation: Int,
        context: ModelContext,
        language: AppLanguage,
        force: Bool,
        trigger: String,
        dashboard: DashboardData?,
        profile: ProfileSettings?
    ) {
        Task { [weak self] in
            guard let self else { return }
            await self.loadEnrichment(
                generation: generation,
                context: context,
                language: language,
                force: force,
                trigger: trigger,
                dashboard: dashboard,
                profile: profile
            )
        }
    }

    private func loadEnrichment(
        generation: Int,
        context: ModelContext,
        language: AppLanguage,
        force: Bool,
        trigger: String,
        dashboard: DashboardData?,
        profile: ProfileSettings?
    ) async {
        isEnrichmentSyncing = true
        defer {
            if generation == syncGeneration {
                isEnrichmentSyncing = false
            }
        }

        let resolvedDashboard = dashboard ?? remoteContext?.dashboard
        let resolvedProfile = profile ?? remoteContext?.profile

        async let scienceTask: [ScienceArticle] = loadScienceArticles(
            language: language,
            dashboard: resolvedDashboard,
            profile: resolvedProfile
        )
        async let proactiveBriefTask: ProactiveCareBrief? = loadProactiveBrief(language: language, force: force)

        let scienceArticles = await scienceTask
        let proactiveBrief = await proactiveBriefTask

        guard generation == syncGeneration else { return }
        guard remoteContext != nil || !scienceArticles.isEmpty || proactiveBrief != nil else { return }

        if let current = remoteContext {
            remoteContext = A10ShellRemoteContext(
                dashboard: current.dashboard,
                recommendations: current.recommendations,
                scienceArticles: scienceArticles.isEmpty ? current.scienceArticles : scienceArticles,
                habits: current.habits,
                profile: current.profile,
                pendingInquiry: current.pendingInquiry,
                proactiveBrief: proactiveBrief ?? current.proactiveBrief,
                activePlan: current.activePlan,
                refreshedAt: .now
            )
        } else {
            remoteContext = A10ShellRemoteContext(
                dashboard: resolvedDashboard,
                recommendations: [],
                scienceArticles: scienceArticles,
                habits: [],
                profile: resolvedProfile,
                pendingInquiry: nil,
                proactiveBrief: proactiveBrief,
                activePlan: nil,
                refreshedAt: .now
            )
        }

        lastErrorMessage = nil
        lastRemoteSource = "enrichment"

        await supabase.captureUserSignal(
            domain: "a10_shell",
            action: "remote_enriched",
            summary: "\(trigger): science=\(scienceArticles.count), brief=\(proactiveBrief != nil)",
            metadata: [
                "trigger": trigger,
                "science_articles_count": scienceArticles.count,
                "has_proactive_brief": proactiveBrief != nil,
                "has_dashboard": resolvedDashboard != nil,
                "has_profile": resolvedProfile != nil
            ]
        )
    }

    private func applyRemoteData(
        dashboard: DashboardData?,
        recommendations: [DailyAIRecommendationItem],
        habits: [SupabaseManager.HabitStatus],
        profile: ProfileSettings?,
        context: ModelContext,
        language: AppLanguage
    ) throws {
        let snapshot = latestSnapshot(in: context) ?? createSnapshot(context: context, language: language)
        let preferences = latestPreferences(in: context) ?? A10SeedData.createPreferences(context: context, language: language)
        let planDrafts = buildPlanDrafts(habits: habits, recommendations: recommendations, language: language)

        if !planDrafts.isEmpty {
            replacePlans(planDrafts, in: context)
        }

        let inferredStage = inferStage(dashboard: dashboard, recommendations: recommendations, habits: habits)
        if Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: .now) {
            snapshot.stage = snapshot.stage.rank >= inferredStage.rank ? snapshot.stage : inferredStage
        } else {
            snapshot.stage = inferredStage
        }

        snapshot.headline = buildHeadline(
            dashboard: dashboard,
            recommendations: recommendations,
            habits: habits,
            profile: profile,
            language: language
        )
        snapshot.summary = buildSummary(
            dashboard: dashboard,
            profile: profile,
            language: language
        )
        snapshot.evidenceNote = buildEvidenceNote(
            dashboard: dashboard,
            language: language
        )

        if let primaryPlan = planDrafts.first(where: { !$0.isCompleted }) ?? planDrafts.first {
            snapshot.nextActionTitle = primaryPlan.title
            snapshot.nextActionDetail = primaryPlan.detail
        }
        snapshot.stressScore = buildStressScore(dashboard: dashboard, habits: habits)
        snapshot.updatedAt = .now

        preferences.languageCode = language.rawValue
        if let reminders = profile?.reminder_preferences {
            preferences.notificationsEnabled = [reminders.morning, reminders.evening, reminders.breathing].contains(true)
        }
        if dashboard?.hardwareData != nil {
            preferences.healthSyncEnabled = true
        }
        preferences.updatedAt = .now

        try context.save()
    }

    private func replacePlans(_ drafts: [A10RemotePlanDraft], in context: ModelContext) {
        let descriptor = FetchDescriptor<A10ActionPlan>(sortBy: [SortDescriptor(\.sortOrder)])
        let existingPlans = (try? context.fetch(descriptor)) ?? []
        for plan in existingPlans {
            context.delete(plan)
        }

        for (index, draft) in drafts.enumerated() {
            context.insert(
                A10ActionPlan(
                    title: draft.title,
                    detail: draft.detail,
                    effortLabel: draft.effortLabel,
                    estimatedMinutes: draft.estimatedMinutes,
                    isCompleted: draft.isCompleted,
                    remoteID: draft.remoteID,
                    sourceRaw: draft.source.rawValue,
                    sortOrder: index,
                    updatedAt: .now
                )
            )
        }
    }

    private func buildPlanDrafts(
        habits: [SupabaseManager.HabitStatus],
        recommendations: [DailyAIRecommendationItem],
        language: AppLanguage
    ) -> [A10RemotePlanDraft] {
        var drafts = habits.map { habit in
            A10RemotePlanDraft(
                title: habit.title,
                detail: nonEmpty(habit.description) ?? defaultHabitDetail(language: language),
                effortLabel: effortLabel(for: habit.minResistanceLevel, language: language),
                estimatedMinutes: estimatedMinutes(forHabitResistance: habit.minResistanceLevel),
                isCompleted: habit.isCompleted,
                remoteID: habit.id,
                source: .habit
            )
        }

        let recommendationDrafts = recommendations.compactMap { item -> A10RemotePlanDraft? in
            let title = nonEmpty(item.action) ?? nonEmpty(item.title) ?? nonEmpty(item.summary)
            guard let title else { return nil }

            let detailParts = [nonEmpty(item.summary), nonEmpty(item.reason)].compactMap { $0 }
            return A10RemotePlanDraft(
                title: title,
                detail: detailParts.isEmpty ? defaultRecommendationDetail(language: language) : detailParts.joined(separator: " "),
                effortLabel: L10n.text("AI 建议", "AI recommendation", language: language),
                estimatedMinutes: estimateMinutes(from: [item.action, item.title, item.summary, item.reason]),
                isCompleted: false,
                remoteID: item.id,
                source: .recommendation
            )
        }

        if drafts.count < 3 {
            let existingTitles = Set(drafts.map(\.title))
            drafts.append(contentsOf: recommendationDrafts.filter { !existingTitles.contains($0.title) })
        }

        return Array(drafts.prefix(6))
    }

    private func buildHeadline(
        dashboard: DashboardData?,
        recommendations: [DailyAIRecommendationItem],
        habits: [SupabaseManager.HabitStatus],
        profile: ProfileSettings?,
        language: AppLanguage
    ) -> String {
        if let focus = nonEmpty(profile?.current_focus ?? profile?.primary_goal) {
            return language == .en
                ? "Start by collapsing today's state around \(focus)."
                : "今天先围绕「\(focus)」收口状态。"
        }

        if let title = nonEmpty(recommendations.first?.title) {
            return title
        }

        if let aiRecommendation = nonEmpty(dashboard?.todayLog?.ai_recommendation) {
            return aiRecommendation
        }

        if let habit = habits.first(where: { !$0.isCompleted }) ?? habits.first {
            return language == .en
                ? "The smallest useful action now is \(habit.title)."
                : "当前最小可执行动作是：\(habit.title)"
        }

        return L10n.text(
            "先让系统知道你今天最难的点。",
            "Let the system understand your hardest point today first.",
            language: language
        )
    }

    private func buildSummary(
        dashboard: DashboardData?,
        profile: ProfileSettings?,
        language: AppLanguage
    ) -> String {
        var parts: [String] = []

        if let focus = nonEmpty(profile?.current_focus) {
            parts.append(language == .en ? "Current focus: \(focus)" : "当前焦点：\(focus)")
        }

        if let stress = dashboard?.todayLog?.anxiety_level ?? dashboard?.todayLog?.stress_level {
            parts.append(language == .en ? "stress \(stress)/10" : "压力 \(stress)/10")
        }

        if let sleepMinutes = dashboard?.todayLog?.sleep_duration_minutes, sleepMinutes > 0 {
            let sleepHours = Double(sleepMinutes) / 60
            let value = String(format: "%.1f", sleepHours)
            parts.append(language == .en ? "sleep \(value)h" : "睡眠 \(value) 小时")
        }

        if let hrv = dashboard?.hardwareData?.hrv?.value {
            parts.append("HRV \(Int(hrv.rounded()))")
        }

        if let readiness = dashboard?.todayLog?.overall_readiness {
            parts.append(language == .en ? "readiness \(readiness)/100" : "就绪度 \(readiness)/100")
        }

        if parts.isEmpty {
            return L10n.text(
                "远端数据尚未补齐时，壳层会继续使用本地闭环状态。",
                "When remote data is still sparse, the shell keeps working from the local loop state.",
                language: language
            )
        }

        return parts.joined(separator: language == .en ? " | " : "｜")
    }

    private func buildEvidenceNote(
        dashboard: DashboardData?,
        language: AppLanguage
    ) -> String {
        var parts: [String] = []

        if let bodyTension = dashboard?.todayLog?.body_tension {
            parts.append(language == .en ? "body tension \(bodyTension)/10" : "身体紧绷 \(bodyTension)/10")
        }

        if let clarity = dashboard?.todayLog?.mental_clarity {
            parts.append(language == .en ? "clarity \(clarity)/10" : "清晰度 \(clarity)/10")
        }

        if let sleepQuality = nonEmpty(dashboard?.todayLog?.sleep_quality) {
            parts.append(language == .en ? "sleep quality \(sleepQuality)" : "睡眠质量 \(sleepQuality)")
        }

        if let scores = dashboard?.clinicalScaleScores, !scores.isEmpty {
            let scoreText = scores
                .sorted { $0.key < $1.key }
                .prefix(2)
                .map { "\($0.key.uppercased()) \($0.value)" }
                .joined(separator: language == .en ? ", " : "，")
            if !scoreText.isEmpty {
                parts.append(scoreText)
            }
        }

        if parts.isEmpty {
            return L10n.text(
                "已接入 Dashboard、Habits 和 Recommendations，等待更多证据样本。",
                "Dashboard, Habits, and Recommendations are connected; waiting for more evidence samples.",
                language: language
            )
        }

        return parts.joined(separator: language == .en ? " | " : "｜")
    }

    private func inferStage(
        dashboard: DashboardData?,
        recommendations: [DailyAIRecommendationItem],
        habits: [SupabaseManager.HabitStatus]
    ) -> A10LoopStage {
        if habits.contains(where: \.isCompleted) {
            return .action
        }
        if !recommendations.isEmpty || nonEmpty(dashboard?.todayLog?.ai_recommendation) != nil {
            return .evidence
        }
        if dashboard?.todayLog != nil || dashboard?.hardwareData != nil || !(dashboard?.clinicalScaleScores?.isEmpty ?? true) {
            return .calibration
        }
        return .inquiry
    }

    private func buildStressScore(
        dashboard: DashboardData?,
        habits: [SupabaseManager.HabitStatus]
    ) -> Int {
        if let value = dashboard?.todayLog?.anxiety_level ?? dashboard?.todayLog?.stress_level ?? dashboard?.todayLog?.body_tension {
            return min(max(value, 1), 10)
        }

        if let scores = dashboard?.clinicalScaleScores?.values, !scores.isEmpty {
            let average = Double(scores.reduce(0, +)) / Double(scores.count)
            let normalized = Int((average / 2.1).rounded())
            return min(max(normalized, 1), 10)
        }

        if habits.contains(where: \.isCompleted) {
            return 4
        }

        return 6
    }

    private func latestSnapshot(in context: ModelContext) -> A10LoopSnapshot? {
        var descriptor = FetchDescriptor<A10LoopSnapshot>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func latestPreferences(in context: ModelContext) -> A10PreferenceRecord? {
        var descriptor = FetchDescriptor<A10PreferenceRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func createSnapshot(context: ModelContext, language: AppLanguage) -> A10LoopSnapshot {
        let snapshot = A10LoopSnapshot(
            headline: L10n.text("先让系统知道你今天最难的点。", "Let the system understand your hardest point today first.", language: language),
            summary: L10n.text("正在把本地壳层和远端数据桥接到一起。", "Bridging the local shell with remote data.", language: language),
            nextActionTitle: L10n.text("等待远端建议", "Waiting for remote guidance", language: language),
            nextActionDetail: L10n.text("如果远端暂时没有返回，系统会继续使用本地闭环。", "If remote data is still unavailable, the shell keeps using the local loop.", language: language),
            evidenceNote: L10n.text("等待第一批远端证据。", "Waiting for the first remote evidence batch.", language: language),
            currentStageRaw: A10LoopStage.inquiry.rawValue,
            stressScore: 6
        )
        context.insert(snapshot)
        return snapshot
    }

    private func effortLabel(for level: Int?, language: AppLanguage) -> String {
        switch level ?? 2 {
        case ...2:
            return L10n.text("低负担", "Low load", language: language)
        case 3:
            return L10n.text("中负担", "Medium load", language: language)
        default:
            return L10n.text("高价值", "High value", language: language)
        }
    }

    private func estimatedMinutes(forHabitResistance level: Int?) -> Int {
        switch level ?? 2 {
        case ...2:
            return 3
        case 3:
            return 5
        default:
            return 8
        }
    }

    private func estimateMinutes(from texts: [String?]) -> Int {
        let pool = texts.compactMap { $0?.lowercased() }.joined(separator: " ")
        if let match = pool.range(of: #"(\d+)\s*(min|mins|minute|minutes|分钟)"#, options: .regularExpression) {
            let fragment = String(pool[match])
            if let value = Int(fragment.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                return value
            }
        }
        return 5
    }

    private func defaultHabitDetail(language: AppLanguage) -> String {
        L10n.text(
            "把这个动作作为今天的低阻力锚点，先完成再决定是否加码。",
            "Use this as today's low-friction anchor before deciding whether to do more.",
            language: language
        )
    }

    private func defaultRecommendationDetail(language: AppLanguage) -> String {
        L10n.text(
            "这是后端根据今日状态整理出来的优先动作。",
            "This is the backend-prioritized action for today's state.",
            language: language
        )
    }

    private func loadProfileSettings() async -> ProfileSettings? {
        do {
            return try await supabase.getProfileSettings()
        } catch {
            return nil
        }
    }

    private func loadPendingInquiry(language: AppLanguage) async -> InquiryQuestion? {
        do {
            let response = try await supabase.getPendingInquiry(language: language.apiCode)
            return response.inquiry
        } catch {
            return nil
        }
    }

    private func loadProactiveBrief(language: AppLanguage, force: Bool) async -> ProactiveCareBrief? {
        do {
            return try await supabase.generateProactiveCareBrief(
                language: language.apiCode,
                forceRefresh: force
            )
        } catch {
            return nil
        }
    }

    private func loadScienceArticles(
        language: AppLanguage,
        dashboard: DashboardData?,
        profile: ProfileSettings?
    ) async -> [ScienceArticle] {
        let baseArticles = await loadDefault([]) { [self] in
            try await self.supabase.getScienceFeed(language: language.apiCode).articles
        }
        guard !baseArticles.isEmpty else { return [] }

        let personalizationContext = SciencePersonalizationContext(
            language: language,
            userId: supabase.currentUser?.id,
            profile: profile,
            dashboard: dashboard
        )
        return await SciencePersonalizationEngine.personalize(
            articles: baseArticles,
            context: personalizationContext
        )
    }

    private struct ActivePlanSurfaceRow: Decodable {
        let id: String
        let name: String?
        let title: String?
        let progress: Int?
        let status: String?
    }

    private func loadActivePlanSummary() async -> A10ShellActivePlanSummary? {
        guard let user = supabase.currentUser else { return nil }

        let endpoint = "user_plans?user_id=eq.\(user.id)&select=id,name,title,progress,status&status=eq.active&order=updated_at.desc&limit=1"
        let rows: [ActivePlanSurfaceRow] = (try? await supabase.request(endpoint)) ?? []
        guard let row = rows.first else { return nil }

        let title = A10NonEmpty(row.name) ?? A10NonEmpty(row.title) ?? "Plan"
        return A10ShellActivePlanSummary(
            id: row.id,
            title: title,
            progress: max(0, min(100, row.progress ?? 0)),
            status: row.status ?? "active"
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        A10NonEmpty(value)
    }

    private func loadOptional<T>(_ operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

    private func loadDefault<T>(_ fallback: T, operation: @escaping () async throws -> T) async -> T {
        do {
            return try await operation()
        } catch {
            return fallback
        }
    }
}

private struct A10RemotePlanDraft {
    let title: String
    let detail: String
    let effortLabel: String
    let estimatedMinutes: Int
    let isCompleted: Bool
    let remoteID: String?
    let source: A10PlanSource
}

private extension A10LoopStage {
    var rank: Int {
        switch self {
        case .inquiry:
            return 0
        case .calibration:
            return 1
        case .evidence:
            return 2
        case .action:
            return 3
        }
    }
}
