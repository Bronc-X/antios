// DashboardViewModel.swift
// 仪表盘视图模型 - 对齐 Web 端 useDashboard Hook
//
// 功能对照:
// - Web: hooks/domain/useDashboard.ts
// - iOS: 本文件
//
// 数据源:
// - Supabase: daily_wellness_logs, unified_user_profiles
// - Next API: /api/digital-twin/dashboard
// - HealthKit: 作为备用本地数据源

import SwiftUI
import WidgetKit

@MainActor
class DashboardViewModel: ObservableObject {
    
    // MARK: - Published State (对应 useDashboard 返回值)
    
    /// 用户画像
    @Published var profile: UnifiedProfile?
    
    /// 最近 7 天健康日志
    @Published var weeklyLogs: [WellnessLog] = []
    
    /// 穿戴设备数据
    @Published var hardwareData: HardwareData?
    
    /// 数字孪生 Dashboard 数据
    @Published var digitalTwin: DigitalTwinDashboardPayload?

    /// AI 主动问询
    @Published var inquiry: InquiryQuestion?
    @Published var isInquiryLoading = false
    @Published var inquiryError: String?

    /// AI 建议（每日 3-4 条，后台生成）
    @Published var aiRecommendations: [DailyAIRecommendationItem] = []
    @Published var isRecommendationsLoading = false
    @Published var recommendationsError: String?
    @Published var featuredScienceArticle: ScienceArticle?


    /// 反焦虑闭环状态（Thread A 契约）
    @Published var antiAnxietyLoopStatus = AntiAnxietyLoopStatus.initial()
    
    /// 加载状态
    @Published var isLoading = false
    
    /// 数字孪生加载状态
    @Published var loadingDigitalTwin = false
    
    /// 同步状态
    @Published var isSyncing = false
    
    /// 离线状态
    @Published var isOffline = false
    
    /// 错误信息
    @Published var error: String?
    
    // MARK: - Derived Properties (对应 useMemo / computed)
    
    /// 用户显示名称
    var userName: String {
        if let email = supabase.currentUser?.email {
            return email.components(separatedBy: "@").first ?? "探索者"
        }
        return L10n.localized("探索者")
    }
    
    /// 时间问候语
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return L10n.localized("早上好")
        case 12..<18: return L10n.localized("下午好")
        default: return L10n.localized("晚上好")
        }
    }
    
    /// 今日日志
    var todayLog: WellnessLog? {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return weeklyLogs.first { $0.log_date.hasPrefix(String(today)) }
    }
    
    /// 数字孪生 Dashboard 数据（已就绪）
    var digitalTwinDashboard: DigitalTwinDashboardResponse? {
        guard let payload = digitalTwin,
              let dashboardData = payload.dashboardData,
              let adaptivePlan = payload.adaptivePlan,
              let lastAnalyzed = payload.lastAnalyzed else {
            return nil
        }
        return DigitalTwinDashboardResponse(
            dashboardData: dashboardData,
            adaptivePlan: adaptivePlan,
            isStale: payload.isStale ?? false,
            lastAnalyzed: lastAnalyzed
        )
    }

    /// 整体状态分数（严格基于真实日志/后端字段）
    var overallScore: Int? {
        if let readiness = todayLog?.overall_readiness {
            return readiness
        }
        if let score = calculateOverallScoreFromLogs(weeklyLogs) {
            return score
        }
        return calculateOverallScoreFromDigitalTwin(digitalTwinDashboard)
    }
    
    /// 状态标签
    var scoreStatus: String {
        guard let score = overallScore else { return L10n.localized("暂无数据") }
        switch score {
        case 80...100: return L10n.localized("优秀")
        case 60..<80: return L10n.localized("良好")
        case 40..<60: return L10n.localized("一般")
        default: return L10n.localized("需关注")
        }
    }
    
    /// 状态颜色
    var scoreColor: Color {
        guard let score = overallScore else { return .textTertiary }
        switch score {
        case 80...100: return .statusSuccess
        case 60..<80: return .liquidGlassAccent
        case 40..<60: return .statusWarning
        default: return .statusError
        }
    }

    /// 整体趋势（来自数字孪生曲线）
    var overallTrendText: String? {
        guard let trend = calculateOverallTrendFromDigitalTwin(digitalTwinDashboard) else { return nil }
        switch trend {
        case .improving: return L10n.runtime("趋势：上升")
        case .declining: return L10n.runtime("趋势：下降")
        case .stable: return L10n.runtime("趋势：稳定")
        }
    }
    
    /// 平均睡眠时长（小时）
    var averageSleepHours: Double {
        let validLogs = weeklyLogs.compactMap { $0.sleep_duration_minutes }
        guard !validLogs.isEmpty else { return 0 }
        return Double(validLogs.reduce(0, +)) / Double(validLogs.count) / 60.0
    }
    
    /// 平均压力水平
    var averageStress: Double {
        let validLogs = weeklyLogs.compactMap { $0.stress_level }
        guard !validLogs.isEmpty else { return 0 }
        return Double(validLogs.reduce(0, +)) / Double(validLogs.count)
    }
    
    /// Digital Twin 是否可用
    var hasDigitalTwin: Bool {
        digitalTwinDashboard != nil
    }

    var hasVerifiedScienceEvidence: Bool {
        guard let article = featuredScienceArticle else { return false }
        guard article.id != "local-science-fallback" else { return false }
        guard hasSufficientHealthSignalsForScience else { return false }

        let hasSummary = !(article.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSource = !(article.sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSourceURL = !(article.sourceUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPersonalReason = !(article.whyRecommended ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return hasSummary && hasSource && hasSourceURL && hasPersonalReason
    }

    var hasSufficientHealthSignalsForScience: Bool {
        let hasCalibrationSignals = todayLog?.anxiety_level != nil || todayLog?.stress_level != nil || todayLog?.sleep_duration_minutes != nil
        let hasWearableSignals = hardwareData?.hrv?.value != nil || hardwareData?.resting_heart_rate?.value != nil || hardwareData?.steps?.value != nil || hardwareData?.sleep_score?.value != nil
        return hasCalibrationSignals || hasWearableSignals
    }

    var scienceEvidenceSnapshot: String {
        var parts: [String] = []
        if let anxiety = todayLog?.anxiety_level { parts.append("焦虑 \(anxiety)/10") }
        if let stress = todayLog?.stress_level { parts.append("压力 \(stress)/10") }
        if let sleepMinutes = todayLog?.sleep_duration_minutes {
            let hours = Double(sleepMinutes) / 60.0
            parts.append("睡眠 \(String(format: "%.1f", hours))h")
        }
        if let hrv = hardwareData?.hrv?.value { parts.append("HRV \(Int(hrv.rounded()))") }
        if let rhr = hardwareData?.resting_heart_rate?.value { parts.append("静息心率 \(Int(rhr.rounded()))") }
        if let steps = hardwareData?.steps?.value { parts.append("步数 \(Int(steps.rounded()))") }
        if parts.isEmpty {
            return "暂无可用于个性化解释的健康数据（请先完成校准并同步 Apple Watch/HealthKit）"
        }
        return parts.joined(separator: " · ")
    }
    
    /// 关键洞察（来自数字孪生汇总）
    var keyInsights: [String] {
        guard let dashboard = digitalTwinDashboard else { return [] }
        var insights: [String] = []
        let summary = dashboard.dashboardData.summaryStats
        if !summary.overallImprovement.isEmpty {
            insights.append("\(L10n.localized("整体改善"))：\(L10n.runtime(summary.overallImprovement))")
        }
        if !summary.consistencyScore.isEmpty {
            insights.append("\(L10n.localized("一致性"))：\(L10n.runtime(summary.consistencyScore))")
        }
        if let baseline = dashboard.dashboardData.baselineData.assessments.first {
            insights.append("\(L10n.runtime(baseline.name))：\(L10n.runtime(baseline.value))")
        }
        return insights
    }
    
    /// 今日 AI 建议
    var aiRecommendation: String? {
        nil
    }

    /// Digital Twin 状态
    var digitalTwinStatus: String? {
        digitalTwin?.status
    }

    var digitalTwinStatusMessage: String {
        if let message = digitalTwin?.message, !message.isEmpty {
            return L10n.runtime(message)
        }
        if digitalTwinDashboard != nil {
            return L10n.localized("预测数据已就绪")
        }
        return L10n.localized("暂无数据")
    }

    var digitalTwinCollectionStatus: DataCollectionStatus? {
        digitalTwin?.collectionStatus
    }
    
    // MARK: - Dependencies
    
    private let supabase = SupabaseManager.shared
    private let healthKit = HealthKitService.shared
    
    // MARK: - Cache (对应 Web 端的 in-memory cache)
    
    private static var cachedData: DashboardData?
    private static var lastFetchTime: Date?
    private static var cachedTwin: DigitalTwinDashboardPayload?
    private static var lastTwinFetchTime: Date?
    private static let staleTime: TimeInterval = 30 // 30 秒
    private static var lastInquiryUserId: String?
    private static var lastInquiryToken: String?

    private let recommendationsCacheKey = "daily_ai_recommendations_cache"
    private let recommendationsTriggerKeyPrefix = "daily_ai_recommendations_trigger_"
    
    private var isCacheStale: Bool {
        guard let lastFetch = Self.lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) > Self.staleTime
    }

    private var isTwinCacheStale: Bool {
        guard let lastFetch = Self.lastTwinFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) > Self.staleTime
    }
    
    // MARK: - Initialization
    
    init() {
        // 从缓存恢复数据
        if let cached = Self.cachedData {
            self.profile = cached.profile
            self.weeklyLogs = cached.weeklyLogs
            self.hardwareData = cached.hardwareData
        }
        if let cachedTwin = Self.cachedTwin {
            self.digitalTwin = cachedTwin
        }
    }
    
    // MARK: - Data Fetching (对应 fetchData)
    
    /// 加载所有 Dashboard 数据
    func loadData(force: Bool = false) async {
        guard !isLoading || force else { return }
        if !force && !isCacheStale && Self.cachedData != nil { return }

        isLoading = Self.cachedData == nil
        error = nil

        do {
            let data = try await supabase.getDashboardData()
            self.profile = data.profile
            self.weeklyLogs = data.weeklyLogs
            self.hardwareData = data.hardwareData

            Self.cachedData = DashboardData(
                profile: data.profile,
                weeklyLogs: data.weeklyLogs,
                hardwareData: data.hardwareData
            )
            Self.lastFetchTime = Date()

            isOffline = false

            syncToWidget()
            refreshAntiAnxietyLoopStatus()

            if data.hardwareData == nil {
                Task { [weak self] in
                    guard let self else { return }
                    let fallbackHardware = await self.loadHardwareData()
                    guard let fallbackHardware else { return }
                    if self.hardwareData == nil {
                        self.hardwareData = fallbackHardware
                        Self.cachedData = DashboardData(
                            profile: self.profile,
                            weeklyLogs: self.weeklyLogs,
                            hardwareData: fallbackHardware
                        )
                        self.syncToWidget()
                        self.refreshAntiAnxietyLoopStatus()
                    }
                }
            }
        } catch {
            self.isOffline = true
            if self.hardwareData == nil {
                self.hardwareData = await loadFromHealthKit()
            }
            self.error = "云端连接异常，已切换本地模式，你仍可继续使用闭环。"
            print("[Dashboard] Load error: \(error)")
            refreshAntiAnxietyLoopStatus()
        }

        isLoading = false
    }
    
    /// 加载穿戴设备/HealthKit 数据
    private func loadHardwareData() async -> HardwareData? {
        // 优先从 Supabase 获取
        let supabaseData = try? await supabase.getHardwareData()
        if let data = supabaseData, data.hrv != nil || data.resting_heart_rate != nil {
            return data
        }
        
        // 备用：从 HealthKit 获取
        return await loadFromHealthKit()
    }
    
    /// 从 HealthKit 加载数据
    private func loadFromHealthKit() async -> HardwareData? {
        guard healthKit.isAvailable else { return nil }

        do {
            let bundle = try await healthKit.collectAppleWatchIngestionBundle()
            guard bundle.hasPayload else { return nil }

            var hardware = HardwareData()
            for snapshot in bundle.snapshots {
                let point = HardwareDataPoint(
                    value: snapshot.value,
                    source: snapshot.source,
                    recorded_at: snapshot.recordedAt
                )
                switch snapshot.metricType {
                case "hrv":
                    hardware.hrv = point
                case "resting_heart_rate":
                    hardware.resting_heart_rate = point
                case "steps":
                    hardware.steps = point
                case "sleep_score":
                    hardware.sleep_score = point
                default:
                    break
                }
            }

            // 后台入链：不阻塞首页渲染，但仍进入用户画像与 RAG 链路。
            Task {
                try? await supabase.syncAppleWatchDataPipeline(bundle)
            }
            return hardware
        } catch {
            print("[Dashboard] HealthKit ingest error: \(error)")
            return nil
        }
    }
    
    // MARK: - Digital Twin (对应 loadDigitalTwin, analyzeDigitalTwin)
    
    /// 加载数字孪生数据
    func loadDigitalTwin(force: Bool = false) async {
        guard !loadingDigitalTwin else { return }
        if !force && !isTwinCacheStale, let cached = Self.cachedTwin {
            self.digitalTwin = cached
            return
        }

        loadingDigitalTwin = true
        defer { loadingDigitalTwin = false }

        do {
            let payload = try await supabase.getDigitalTwinDashboard()
            self.digitalTwin = payload
            Self.cachedTwin = payload
            Self.lastTwinFetchTime = Date()
        } catch {
            print("[Dashboard] Digital Twin load error: \(error)")
        }
    }
    
    /// 触发数字孪生分析（调用 API）
    func analyzeDigitalTwin(forceRefresh: Bool = true) async -> Bool {
        loadingDigitalTwin = true
        error = nil
        
        defer { loadingDigitalTwin = false }

        let result = await supabase.triggerDigitalTwinAnalysis(forceRefresh: forceRefresh)
        if result.triggered {
            await loadDigitalTwin(force: true)
            return digitalTwinDashboard != nil
        }

        error = result.reason
        return false
    }

    // MARK: - AI Inquiry (主动问询)

    func loadInquiry(language: String, force: Bool = false) async {
        guard shouldRefreshInquiry(force: force) else { return }
        isInquiryLoading = true
        inquiryError = nil
        do {
            let response = try await supabase.getPendingInquiry(language: language)
            inquiry = response.hasInquiry ? response.inquiry : nil
            refreshAntiAnxietyLoopStatus()
        } catch {
            inquiry = nil
            inquiryError = error.localizedDescription
            refreshAntiAnxietyLoopStatus()
        }
        isInquiryLoading = false
    }

    private func shouldRefreshInquiry(force: Bool) -> Bool {
        if force { return true }
        guard let userId = supabase.currentUser?.id else { return false }
        let token = UserDefaults.standard.string(forKey: "supabase_access_token") ?? ""
        if Self.lastInquiryUserId != userId || Self.lastInquiryToken != token {
            Self.lastInquiryUserId = userId
            Self.lastInquiryToken = token
            return true
        }
        return inquiry == nil
    }

    func respondInquiry(option: InquiryOption) async {
        guard let inquiry else { return }
        isInquiryLoading = true
        inquiryError = nil
        do {
            _ = try await supabase.respondInquiry(inquiryId: inquiry.id, response: option.value)
            self.inquiry = nil
            await loadData(force: true)
            refreshAntiAnxietyLoopStatus()
        } catch {
            inquiryError = error.localizedDescription
            refreshAntiAnxietyLoopStatus()
        }
        isInquiryLoading = false
    }

    func dismissInquiry() {
        inquiry = nil
        refreshAntiAnxietyLoopStatus()
    }

    // MARK: - AI Recommendations (每日 3-4 条，后台生成)

    func loadDailyRecommendations(language: String, force: Bool = false) async {
        if aiRecommendations.isEmpty {
            isRecommendationsLoading = true
        }
        recommendationsError = nil
        let now = Date()

        do {
            let items = try await supabase.getDailyRecommendations(date: now)
            if !items.isEmpty {
                aiRecommendations = items
                saveRecommendationsCache(items, date: now)
            } else if let cached = loadRecommendationsCache(for: now) {
                aiRecommendations = cached
            } else {
                aiRecommendations = localFallbackRecommendations()
            }

            if items.isEmpty && shouldTriggerRecommendations(for: now, force: force) {
                Task.detached { [language] in
                    await SupabaseManager.shared.triggerDailyRecommendations(force: force, language: language)
                }
            }

            await loadFeaturedScienceArticle(language: language, force: force)
            refreshAntiAnxietyLoopStatus()
        } catch {
            recommendationsError = "云端建议暂不可用，已切换本地建议。"
            if let cached = loadRecommendationsCache(for: now) {
                aiRecommendations = cached
            } else {
                aiRecommendations = localFallbackRecommendations()
            }
            await loadFeaturedScienceArticle(language: language, force: force)
            refreshAntiAnxietyLoopStatus()
        }

        isRecommendationsLoading = false
    }

    private func loadRecommendationsCache(for date: Date) -> [DailyAIRecommendationItem]? {
        guard let data = UserDefaults.standard.data(forKey: recommendationsCacheKey),
              let cache = try? JSONDecoder().decode(DailyAIRecommendationCache.self, from: data) else {
            return nil
        }
        let dayString = cache.date
        if dayString == DailyAIRecommendationCache.dateString(from: date) {
            return cache.items
        }
        return nil
    }

    private func saveRecommendationsCache(_ items: [DailyAIRecommendationItem], date: Date) {
        let cache = DailyAIRecommendationCache(date: DailyAIRecommendationCache.dateString(from: date), items: items)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: recommendationsCacheKey)
        }
    }

    private func shouldTriggerRecommendations(for date: Date, force: Bool) -> Bool {
        if force { return true }
        let dayString = DailyAIRecommendationCache.dateString(from: date)
        let key = "\(recommendationsTriggerKeyPrefix)\(dayString)"
        if UserDefaults.standard.bool(forKey: key) {
            return false
        }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    private func loadFeaturedScienceArticle(language: String, force: Bool) async {
        if hasVerifiedScienceEvidence && !force {
            return
        }

        guard hasSufficientHealthSignalsForScience else {
            featuredScienceArticle = nil
            recommendationsError = "缺少真实健康信号，暂不展示科学解释。请先完成校准或同步 Apple Watch/HealthKit。"
            return
        }

        do {
            let response = try await supabase.getScienceFeed(language: language)
            let candidate = response.articles.first(where: { $0.isRecommended == true }) ?? response.articles.first
            if let candidate, isVerifiedScienceArticle(candidate) {
                featuredScienceArticle = candidate
            } else {
                featuredScienceArticle = nil
                recommendationsError = "个性化科学解释暂未就绪，请先同步真实健康数据后重试。"
            }
        } catch {
            featuredScienceArticle = nil
            if recommendationsError == nil {
                recommendationsError = "科学解释服务暂不可用，请稍后重试。"
            }
        }
    }

    private func isVerifiedScienceArticle(_ article: ScienceArticle) -> Bool {
        if article.id == "local-science-fallback" { return false }
        guard hasSufficientHealthSignalsForScience else { return false }

        let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (article.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (article.sourceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceUrl = (article.sourceUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (article.whyRecommended ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return !title.isEmpty && !summary.isEmpty && !source.isEmpty && !sourceUrl.isEmpty && !reason.isEmpty
    }


    private func localFallbackRecommendations() -> [DailyAIRecommendationItem] {
        let stress = todayLog?.stress_level ?? Int(averageStress.rounded())
        let sleepHours = averageSleepHours

        var items: [DailyAIRecommendationItem] = []

        if stress >= 7 {
            items.append(
                DailyAIRecommendationItem(
                    title: "先降生理唤醒",
                    summary: "当前压力偏高，先让神经系统降速会更容易恢复。",
                    action: "做 3 分钟慢呼吸（吸4秒-呼6秒）",
                    reason: "焦虑高唤醒时，先调呼吸比先讲道理更有效"
                )
            )
        }

        if sleepHours > 0, sleepHours < 6.5 {
            items.append(
                DailyAIRecommendationItem(
                    title: "优先修复睡眠窗口",
                    summary: "睡眠偏短会放大威胁感知与紧张反应。",
                    action: "今晚固定上床时间，睡前 60 分钟降刺激",
                    reason: "稳定睡眠节律可降低次日焦虑波动"
                )
            )
        }

        items.append(
            DailyAIRecommendationItem(
                title: "微动作闭环",
                summary: "小步行动更容易坚持并形成正反馈。",
                action: "完成 8 分钟轻步行，并在结束后打分体感（0-10）",
                reason: "可执行动作 + 复盘能快速提升可控感"
            )
        )

        return Array(items.prefix(3))
    }

    // MARK: - Sync (对应 sync)
    
    /// 同步用户画像
    func sync() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        error = nil
        
        defer { isSyncing = false }
        
        // 刷新所有数据
        await loadData(force: true)
        
        // 如果有数字孪生，也刷新
        if digitalTwin != nil {
            await loadDigitalTwin()
        }
    }
    
    // MARK: - Refresh (对应 refresh)
    
    /// 刷新数据（用于下拉刷新）
    func refresh() async {
        await loadData(force: true)
        await loadDigitalTwin()
        refreshAntiAnxietyLoopStatus()
    }

    // MARK: - Anti-anxiety Loop Orchestration

    private func refreshAntiAnxietyLoopStatus() {
        let now = ISO8601DateFormatter().string(from: Date())
        var completed: [AntiAnxietyLoopStep] = []
        var blocked: [String] = []

        if inquiry == nil {
            completed.append(.proactiveInquiry)
        }

        if todayLog != nil {
            completed.append(.dailyCalibration)
        } else {
            blocked.append("可选：补一条今日校准，建议会更贴合你")
        }

        if hasVerifiedScienceEvidence {
            completed.append(.scientificExplanation)
        } else {
            blocked.append("科学解释整理中，先执行一个低负担动作即可")
        }

        if hasActionClosureSignal {
            completed.append(.actionClosure)
        } else {
            blocked.append("可选：执行后告诉 Max 体感变化，便于下一轮跟进")
        }

        let currentStep = AntiAnxietyLoopStep.allCases.first { !completed.contains($0) } ?? .actionClosure
        antiAnxietyLoopStatus = AntiAnxietyLoopStatus(
            currentStep: currentStep,
            completedSteps: completed,
            blockedReasons: blocked,
            updatedAt: now
        )
    }

    private var hasActionClosureSignal: Bool {
        aiRecommendations.contains { item in
            !item.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    // MARK: - Widget Sync
    
    private func syncToWidget() {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.youngtony") else {
            return
        }

        if let score = overallScore {
            sharedDefaults.set(score, forKey: "widget_anxietyScore")
        } else {
            sharedDefaults.removeObject(forKey: "widget_anxietyScore")
        }
        sharedDefaults.set(hardwareData?.hrv?.value ?? 0, forKey: "widget_hrv")
        sharedDefaults.set(hardwareData?.resting_heart_rate?.value ?? 0, forKey: "widget_restingHeartRate")
        sharedDefaults.set(averageSleepHours, forKey: "widget_sleepDuration")
        sharedDefaults.set(averageSleepHours, forKey: "widget_sleepHours")
        sharedDefaults.set(hardwareData?.steps?.value ?? 0, forKey: "widget_steps")
        sharedDefaults.set(Date(), forKey: "widget_lastUpdate")
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Strict Score Mapping (对齐 Web data-mapping)

    private func calculateOverallScoreFromLogs(_ logs: [WellnessLog]) -> Int? {
        let minLogCount = 3
        guard logs.count >= minLogCount else { return nil }

        var sleepSum = 0.0
        var sleepCount = 0
        var stressSum = 0.0
        var stressCount = 0
        var energySum = 0.0
        var energyCount = 0
        var exerciseSum = 0.0
        var exerciseCount = 0
        let hydrationSum = 0.0
        let hydrationCount = 0

        for log in logs {
            if let minutes = log.sleep_duration_minutes {
                let hours = Double(minutes) / 60.0
                var score: Double
                if hours >= 7 && hours <= 9 {
                    score = 100
                } else if hours >= 6 && hours < 7 {
                    score = 75
                } else if hours > 9 && hours <= 10 {
                    score = 75
                } else if hours >= 5 && hours < 6 {
                    score = 50
                } else {
                    score = 25
                }

                if let quality = sleepQualityFactor(log.sleep_quality) {
                    score = score * quality
                }

                sleepSum += score
                sleepCount += 1
            }

            if let stressValue = log.stress_level {
                let normalized = normalizeStressLevel(stressValue)
                let stressScore = Double(6 - normalized) * 20.0
                stressSum += stressScore
                stressCount += 1
            }

            if let energyValue = log.morning_energy ?? log.energy_level {
                let energyScore = Double(energyValue) * 20.0
                energySum += energyScore
                energyCount += 1
            }

            if let minutes = log.exercise_duration_minutes {
                let score: Double
                if minutes >= 30 {
                    score = min(100, (Double(minutes) / 60.0) * 100)
                } else {
                    score = (Double(minutes) / 30.0) * 60
                }
                exerciseSum += score
                exerciseCount += 1
            }

        }

        let sleepScore = sleepCount > 0 ? sleepSum / Double(sleepCount) : 0
        let stressScore = stressCount > 0 ? stressSum / Double(stressCount) : 0
        let energyScore = energyCount > 0 ? energySum / Double(energyCount) : 0
        let exerciseScore = exerciseCount > 0 ? exerciseSum / Double(exerciseCount) : 0
        let hydrationScore = hydrationCount > 0 ? hydrationSum / Double(hydrationCount) : 0

        let totalFields = 5.0
        let filledFields = Double([sleepCount, stressCount, energyCount, exerciseCount, hydrationCount].filter { $0 > 0 }.count)
        let dataQuality = filledFields / totalFields
        guard dataQuality >= 0.5 else { return nil }

        let overallScore = (sleepScore + stressScore + energyScore + exerciseScore + hydrationScore) / totalFields
        return Int(round(overallScore))
    }

    private func calculateOverallScoreFromDigitalTwin(_ dashboard: DigitalTwinDashboardResponse?) -> Int? {
        guard let charts = dashboard?.dashboardData.charts else { return nil }
        let anxiety = charts.anxietyTrend.last.map { 100 - $0 }
        let sleep = charts.sleepTrend.last
        let energy = charts.energyTrend.last
        let hrv = charts.hrvTrend.last

        let values = [anxiety, sleep, energy, hrv].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        let avg = values.reduce(0, +) / Double(values.count)
        return Int(avg.rounded())
    }

    private enum OverallTrend {
        case improving
        case stable
        case declining
    }

    private func calculateOverallTrendFromDigitalTwin(_ dashboard: DigitalTwinDashboardResponse?) -> OverallTrend? {
        guard let charts = dashboard?.dashboardData.charts else { return nil }
        let count = charts.anxietyTrend.count
        guard count >= 2 else { return nil }

        let current = averageDigitalTwinScore(
            anxiety: charts.anxietyTrend.last,
            sleep: charts.sleepTrend.last,
            energy: charts.energyTrend.last,
            hrv: charts.hrvTrend.last
        )
        let previous = averageDigitalTwinScore(
            anxiety: charts.anxietyTrend.dropLast().last,
            sleep: charts.sleepTrend.dropLast().last,
            energy: charts.energyTrend.dropLast().last,
            hrv: charts.hrvTrend.dropLast().last
        )

        guard let curr = current, let prev = previous else { return nil }
        let delta = curr - prev
        if delta > 2 { return .improving }
        if delta < -2 { return .declining }
        return .stable
    }

    private func averageDigitalTwinScore(
        anxiety: Double?,
        sleep: Double?,
        energy: Double?,
        hrv: Double?
    ) -> Double? {
        let transformedAnxiety = anxiety.map { 100 - $0 }
        let values = [transformedAnxiety, sleep, energy, hrv].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func sleepQualityFactor(_ value: String?) -> Double? {
        guard let value else { return nil }
        if let numeric = Double(value) {
            return max(0.0, min(1.0, numeric / 5.0))
        }
        switch value.lowercased() {
        case "excellent": return 1.0
        case "good": return 0.9
        case "average": return 0.7
        case "poor": return 0.4
        default: return nil
        }
    }

    private func normalizeStressLevel(_ value: Int) -> Int {
        if value <= 5 { return max(1, value) }
        let normalized = Int(round(Double(value) / 2.0))
        return min(5, max(1, normalized))
    }
}

private struct DailyAIRecommendationCache: Codable {
    let date: String
    let items: [DailyAIRecommendationItem]

    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
