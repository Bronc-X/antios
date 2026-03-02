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
import UserNotifications

@MainActor
class DashboardViewModel: ObservableObject {
    
    // MARK: - Published State (对应 useDashboard 返回值)
    
    /// 用户画像
    @Published var profile: UnifiedProfile?
    
    /// 最近 7 天健康日志
    @Published var weeklyLogs: [WellnessLog] = []
    
    /// 穿戴设备数据
    @Published var hardwareData: HardwareData?

    /// 临床问卷基线分（来自 profiles.inferred_scale_scores）
    @Published var clinicalScaleScores: [String: Int]?
    
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
    @Published var proactiveCareBrief: ProactiveCareBrief?
    @Published var proactiveBriefError: String?


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
        return t("探索者", "Explorer")
    }
    
    /// 时间问候语
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return t("早上好", "Good morning")
        case 12..<18: return t("下午好", "Good afternoon")
        default: return t("晚上好", "Good evening")
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
            return min(max(readiness, 0), 100)
        }
        return calculateUnifiedStabilityScore()
    }
    
    /// 状态标签
    var scoreStatus: String {
        guard let score = overallScore else { return t("暂无数据", "No data yet") }
        switch score {
        case 80...100: return t("优秀", "Excellent")
        case 60..<80: return t("良好", "Good")
        case 40..<60: return t("一般", "Average")
        default: return t("需关注", "Needs attention")
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
        case .improving: return t("趋势：上升", "Trend: Rising")
        case .declining: return t("趋势：下降", "Trend: Falling")
        case .stable: return t("趋势：稳定", "Trend: Stable")
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
        if let anxiety = todayLog?.anxiety_level { parts.append(t("焦虑 \(anxiety)/10", "Anxiety \(anxiety)/10")) }
        if let stress = todayLog?.stress_level { parts.append(t("压力 \(stress)/10", "Stress \(stress)/10")) }
        if let sleepMinutes = todayLog?.sleep_duration_minutes {
            let hours = Double(sleepMinutes) / 60.0
            parts.append(t("睡眠 \(String(format: "%.1f", hours))h", "Sleep \(String(format: "%.1f", hours))h"))
        }
        if let hrv = hardwareData?.hrv?.value { parts.append("HRV \(Int(hrv.rounded()))") }
        if let rhr = hardwareData?.resting_heart_rate?.value { parts.append(t("静息心率 \(Int(rhr.rounded()))", "Resting heart rate \(Int(rhr.rounded()))")) }
        if let steps = hardwareData?.steps?.value { parts.append(t("步数 \(Int(steps.rounded()))", "Steps \(Int(steps.rounded()))")) }
        if parts.isEmpty {
            return t("暂无可用于个性化解释的健康数据（请先完成校准并同步 Apple Watch/HealthKit）", "No health data available for personalized explanations yet (complete calibration and sync Apple Watch/HealthKit first).")
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
            return r(message)
        }
        if digitalTwinDashboard != nil {
            return t("预测数据已就绪", "Prediction data is ready")
        }
        return t("暂无数据", "No data yet")
    }

    var digitalTwinCollectionStatus: DataCollectionStatus? {
        digitalTwin?.collectionStatus
    }
    
    // MARK: - Dependencies
    
    private let supabase = SupabaseManager.shared
    private let healthKit = HealthKitService.shared

    private var language: AppLanguage { L10n.currentLanguage() }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.text(zh, en, language: language)
    }

    private func r(_ value: String) -> String {
        L10n.runtime(value, language: language)
    }
    
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
    private let proactiveBriefNotifiedDayKey = "proactive_brief_last_notified_day"
    private let proactiveBriefNotifiedFingerprintKey = "proactive_brief_last_notified_fingerprint"
    private let proactiveBriefNotificationIdentifierPrefix = "proactive-care-brief-"
    
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
            self.clinicalScaleScores = cached.clinicalScaleScores
        }
        if let cachedTwin = Self.cachedTwin {
            self.digitalTwin = cachedTwin
        }
    }
    
    // MARK: - Data Fetching (对应 fetchData)
    
    /// 加载所有 Dashboard 数据
    func loadData(force: Bool = false) async {
        guard !isLoading || force else { return }
        if !force, !isCacheStale, let cached = Self.cachedData {
            let hasClinicalScores = !(cached.clinicalScaleScores?.isEmpty ?? true)
            // 临床评估刚完成时，若缓存里还没有量表分，强制走一次远端拉取，保证首登即见分数。
            if !supabase.isClinicalComplete || hasClinicalScores {
                return
            }
        }

        isLoading = Self.cachedData == nil
        error = nil

        do {
            let data = try await supabase.getDashboardData()
            self.profile = data.profile
            self.weeklyLogs = data.weeklyLogs
            self.hardwareData = data.hardwareData
            self.clinicalScaleScores = data.clinicalScaleScores

            Self.cachedData = DashboardData(
                profile: data.profile,
                weeklyLogs: data.weeklyLogs,
                hardwareData: data.hardwareData,
                clinicalScaleScores: data.clinicalScaleScores
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
                            hardwareData: fallbackHardware,
                            clinicalScaleScores: self.clinicalScaleScores
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
            self.error = t("云端连接异常，已切换本地模式，你仍可继续使用主要功能。", "Cloud connection unavailable. Switched to local mode; you can continue using core features.")
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
                do {
                    try await supabase.syncAppleWatchDataPipeline(bundle)
                } catch {
                    print("[Dashboard] Apple Watch sync pipeline failed: \(error)")
                }
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
            await loadProactiveCareBrief(language: language, force: force)
            refreshAntiAnxietyLoopStatus()
        } catch {
            recommendationsError = t("云端建议暂不可用，已切换本地建议。", "Cloud recommendations are unavailable. Switched to local recommendations.")
            if let cached = loadRecommendationsCache(for: now) {
                aiRecommendations = cached
            } else {
                aiRecommendations = localFallbackRecommendations()
            }
            await loadFeaturedScienceArticle(language: language, force: force)
            await loadProactiveCareBrief(language: language, force: force)
            refreshAntiAnxietyLoopStatus()
        }

        isRecommendationsLoading = false
    }

    private func loadProactiveCareBrief(language: String, force: Bool) async {
        do {
            proactiveCareBrief = try await supabase.generateProactiveCareBrief(
                language: language,
                forceRefresh: force
            )
            proactiveBriefError = nil
            if let proactiveCareBrief {
                await scheduleProactiveBriefNotificationIfNeeded(
                    proactiveCareBrief,
                    force: force
                )
            }
        } catch {
            proactiveBriefError = error.localizedDescription
            if force {
                proactiveCareBrief = nil
            }
        }
    }

    private func scheduleProactiveBriefNotificationIfNeeded(
        _ brief: ProactiveCareBrief,
        force: Bool
    ) async {
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.object(forKey: "settings_notifications_enabled") as? Bool ?? false
        let remindersEnabled = defaults.object(forKey: "settings_daily_reminder_enabled") as? Bool ?? false
        guard notificationsEnabled, remindersEnabled else { return }
        guard await currentNotificationPermissionGranted() else { return }

        let dayKey = DailyAIRecommendationCache.dateString(from: Date())
        let fingerprint = briefFingerprint(brief)
        let lastDay = defaults.string(forKey: proactiveBriefNotifiedDayKey)
        let lastFingerprint = defaults.string(forKey: proactiveBriefNotifiedFingerprintKey)
        if !force, lastDay == dayKey, lastFingerprint == fingerprint {
            return
        }

        let configuredDelay = defaults.integer(forKey: "settings_proactive_brief_delay_minutes")
        let delayMinutes = configuredDelay > 0
            ? min(180, max(5, configuredDelay))
            : 45
        let triggerSeconds = TimeInterval(delayMinutes * 60)
        let identifier = "\(proactiveBriefNotificationIdentifierPrefix)\(dayKey)"

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = t("Max 今日科学关怀", "Max daily scientific care")
        content.body = "\(brief.title) · \(brief.microAction)"
        content.sound = .default
        let prompt = language == .en
            ? "I saw your proactive care card. I completed: \(brief.microAction). Please continue with: \(brief.followUpQuestion)"
            : "我看到你的主动关怀卡了。我已执行：\(brief.microAction)。请继续跟进：\(brief.followUpQuestion)"
        content.userInfo = [
            "route": "max",
            "source": "proactive_brief",
            "brief_id": brief.id,
            "prompt": prompt
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, triggerSeconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            defaults.set(dayKey, forKey: proactiveBriefNotifiedDayKey)
            defaults.set(fingerprint, forKey: proactiveBriefNotifiedFingerprintKey)
        } catch {
            print("[Dashboard] proactive brief notification schedule error: \(error)")
        }
    }

    private func currentNotificationPermissionGranted() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                continuation.resume(returning: granted)
            }
        }
    }

    private func briefFingerprint(_ brief: ProactiveCareBrief) -> String {
        "\(brief.title)|\(brief.microAction)|\(brief.followUpQuestion)"
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
            recommendationsError = t("缺少真实健康信号，暂不展示科学解释。请先完成校准或同步 Apple Watch/HealthKit。", "Missing real health signals, so scientific explanations are hidden. Complete calibration or sync Apple Watch/HealthKit first.")
            return
        }

        do {
            let response = try await supabase.getScienceFeed(language: language)
            let candidate = response.articles.first(where: { $0.isRecommended == true }) ?? response.articles.first
            if let candidate, isVerifiedScienceArticle(candidate) {
                featuredScienceArticle = candidate
            } else {
                featuredScienceArticle = nil
                recommendationsError = t("个性化科学解释暂未就绪，请先同步真实健康数据后重试。", "Personalized scientific explanation is not ready yet. Sync real health data and try again.")
            }
        } catch {
            featuredScienceArticle = nil
            if recommendationsError == nil {
                recommendationsError = t("科学解释服务暂不可用，请稍后重试。", "Scientific explanation service is temporarily unavailable. Please try again later.")
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
                    title: t("先降生理唤醒", "Reduce physiological arousal first"),
                    summary: t("当前压力偏高，先让神经系统降速会更容易恢复。", "Stress is high right now. Slowing your nervous system first makes recovery easier."),
                    action: t("做 3 分钟慢呼吸（吸4秒-呼6秒）", "Do 3 minutes of slow breathing (inhale 4s, exhale 6s)."),
                    reason: t("焦虑高唤醒时，先调呼吸比先讲道理更有效", "When anxiety arousal is high, calming breathing works better than reasoning first.")
                )
            )
        }

        if sleepHours > 0, sleepHours < 6.5 {
            items.append(
                DailyAIRecommendationItem(
                    title: t("优先修复睡眠窗口", "Repair sleep window first"),
                    summary: t("睡眠偏短会放大威胁感知与紧张反应。", "Short sleep amplifies threat perception and tension response."),
                    action: t("今晚固定上床时间，睡前 60 分钟降刺激", "Set a fixed bedtime tonight and reduce stimulation 60 minutes before sleep."),
                    reason: t("稳定睡眠节律可降低次日焦虑波动", "A stable sleep rhythm reduces next-day anxiety fluctuations.")
                )
            )
        }

        items.append(
            DailyAIRecommendationItem(
                title: t("微动作跟进", "Micro-action follow-up"),
                summary: t("小步行动更容易坚持并形成正反馈。", "Small actions are easier to sustain and create positive feedback."),
                action: t("完成 8 分钟轻步行，并在结束后打分体感（0-10）", "Complete an 8-minute light walk, then rate your body sensation (0-10)."),
                reason: t("可执行动作 + 复盘能快速提升可控感", "Executable action + review quickly increases sense of control.")
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
            blocked.append(t("可选：补一条今日校准，建议会更贴合你", "Optional: add today's calibration to make recommendations more relevant."))
        }

        if hasVerifiedScienceEvidence || proactiveCareBrief != nil {
            completed.append(.scientificExplanation)
        } else {
            blocked.append(t("科学解释整理中，先执行一个低负担动作即可", "Scientific explanation is being prepared. Start with one low-burden action first."))
        }

        if hasActionClosureSignal {
            completed.append(.actionClosure)
        } else {
            blocked.append(t("可选：执行后告诉 Max 体感变化，便于下一轮跟进", "Optional: after action, tell Max your body sensation change for the next follow-up cycle."))
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
        if let proactiveCareBrief {
            sharedDefaults.set(proactiveCareBrief.title, forKey: "widget_proactive_title")
            sharedDefaults.set(proactiveCareBrief.microAction, forKey: "widget_proactive_action")
            sharedDefaults.set(proactiveCareBrief.followUpQuestion, forKey: "widget_proactive_follow_up")
        } else {
            sharedDefaults.removeObject(forKey: "widget_proactive_title")
            sharedDefaults.removeObject(forKey: "widget_proactive_action")
            sharedDefaults.removeObject(forKey: "widget_proactive_follow_up")
        }
        sharedDefaults.set(Date(), forKey: "widget_lastUpdate")
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Unified Stability Scoring

    private typealias StabilitySignal = (value: Double, reliability: Double)

    /// 统一稳定度分：问卷基线 + 日志 + 设备 + 数字孪生融合（全部基于真实数据）
    private func calculateUnifiedStabilityScore() -> Int? {
        var weightedSignals: [(value: Double, weight: Double)] = []

        if let baseline = calculateBaselineScoreFromClinical(clinicalScaleScores) {
            weightedSignals.append((baseline.value, 0.55 * baseline.reliability))
        }

        if let logScore = calculateOverallScoreFromLogs(weeklyLogs) {
            weightedSignals.append((Double(logScore), 0.30 * logDataReliability(weeklyLogs)))
        }

        if let wearable = calculateWearableScore(hardwareData) {
            weightedSignals.append((wearable.value, 0.10 * wearable.reliability))
        }

        if let twinScore = calculateOverallScoreFromDigitalTwin(digitalTwinDashboard) {
            let twinReliability = digitalTwinDashboard?.isStale == true ? 0.45 : 0.65
            weightedSignals.append((Double(twinScore), 0.05 * twinReliability))
        }

        guard !weightedSignals.isEmpty else { return nil }
        let totalWeight = weightedSignals.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let fusedScore = weightedSignals.reduce(0) { $0 + ($1.value * $1.weight) } / totalWeight
        return Int(round(min(max(fusedScore, 0), 100)))
    }

    /// 日志分：按最近 7 天真实日志做 recency-weighted 聚合
    private func calculateOverallScoreFromLogs(_ logs: [WellnessLog]) -> Int? {
        guard !logs.isEmpty else { return nil }

        var sleepSamples: [(score: Double, daysAgo: Double)] = []
        var stressSamples: [(score: Double, daysAgo: Double)] = []
        var energySamples: [(score: Double, daysAgo: Double)] = []
        var exerciseSamples: [(score: Double, daysAgo: Double)] = []

        for log in logs {
            let daysAgo = daysAgo(from: log.log_date) ?? 7

            if let sleepScore = sleepStabilityScore(from: log) {
                sleepSamples.append((sleepScore, daysAgo))
            }
            if let stressValue = log.stress_level {
                let normalized = normalizeStressLevel(stressValue)
                let stressScore = Double(6 - normalized) * 20.0
                stressSamples.append((stressScore, daysAgo))
            }
            if let energyScore = energyStabilityScore(from: log) {
                energySamples.append((energyScore, daysAgo))
            }
            if let exerciseScore = exerciseStabilityScore(from: log) {
                exerciseSamples.append((exerciseScore, daysAgo))
            }
        }

        let sleepScore = recencyWeightedAverage(sleepSamples)
        let stressScore = recencyWeightedAverage(stressSamples)
        let energyScore = recencyWeightedAverage(energySamples)
        let exerciseScore = recencyWeightedAverage(exerciseSamples)

        var weightedComponents: [(value: Double, weight: Double)] = []
        if let sleepScore { weightedComponents.append((sleepScore, 0.34)) }
        if let stressScore { weightedComponents.append((stressScore, 0.36)) }
        if let energyScore { weightedComponents.append((energyScore, 0.18)) }
        if let exerciseScore { weightedComponents.append((exerciseScore, 0.12)) }

        guard !weightedComponents.isEmpty else { return nil }

        let totalWeight = weightedComponents.reduce(0) { $0 + $1.weight }
        let score = weightedComponents.reduce(0) { $0 + ($1.value * $1.weight) } / totalWeight
        return Int(round(min(max(score, 0), 100)))
    }

    private func calculateBaselineScoreFromClinical(_ rawScores: [String: Int]?) -> StabilitySignal? {
        guard let rawScores, !rawScores.isEmpty else { return nil }

        let gad7Score = clinicalScaleValue("gad7", from: rawScores).flatMap { invertClinicalScale($0, max: 21) }
        let phq9Score = clinicalScaleValue("phq9", from: rawScores).flatMap { invertClinicalScale($0, max: 27) }
        let isiScore = clinicalScaleValue("isi", from: rawScores).flatMap { invertClinicalScale($0, max: 28) }

        // PSS-10 在当前 onboarding 里可能未采集（常见占位值 0），因此仅在 > 0 时纳入。
        let pss10Score: Double? = {
            guard let raw = clinicalScaleValue("pss10", from: rawScores), raw > 0 else { return nil }
            return invertClinicalScale(raw, max: 40)
        }()

        var components: [(value: Double, weight: Double)] = []
        if let gad7Score { components.append((gad7Score, 0.36)) }
        if let phq9Score { components.append((phq9Score, 0.30)) }
        if let isiScore { components.append((isiScore, 0.22)) }
        if let pss10Score { components.append((pss10Score, 0.12)) }

        guard !components.isEmpty else { return nil }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let baselineScore = components.reduce(0) { $0 + ($1.value * $1.weight) } / totalWeight
        let coverage = Double(components.count) / 4.0
        let reliability = min(1.0, 0.55 + coverage * 0.4)
        return (baselineScore, reliability)
    }

    private func calculateWearableScore(_ hardware: HardwareData?) -> StabilitySignal? {
        guard let hardware else { return nil }

        var components: [(value: Double, weight: Double)] = []
        var freshnessDays: [Double] = []

        if let sleepPoint = hardware.sleep_score {
            components.append((min(max(sleepPoint.value, 0), 100), 0.35))
            if let days = daysAgo(from: sleepPoint.recorded_at) { freshnessDays.append(days) }
        }

        if let hrvPoint = hardware.hrv, hrvPoint.value > 0 {
            let score = min(max(((hrvPoint.value - 20.0) / 80.0) * 100.0, 0), 100)
            components.append((score, 0.35))
            if let days = daysAgo(from: hrvPoint.recorded_at) { freshnessDays.append(days) }
        }

        if let rhrPoint = hardware.resting_heart_rate, rhrPoint.value > 0 {
            let score = max(0, 100 - abs(rhrPoint.value - 62) * 2.5)
            components.append((min(score, 100), 0.20))
            if let days = daysAgo(from: rhrPoint.recorded_at) { freshnessDays.append(days) }
        }

        if let stepsPoint = hardware.steps, stepsPoint.value > 0 {
            let score = min(max((stepsPoint.value / 10_000.0) * 100.0, 0), 100)
            components.append((score, 0.10))
            if let days = daysAgo(from: stepsPoint.recorded_at) { freshnessDays.append(days) }
        }

        guard !components.isEmpty else { return nil }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let wearableScore = components.reduce(0) { $0 + ($1.value * $1.weight) } / totalWeight
        let coverage = Double(components.count) / 4.0
        let newestSignalDays = freshnessDays.min() ?? 7
        let freshnessFactor = max(0.6, 1.0 - min(newestSignalDays, 14) / 20.0)
        let reliability = min(1.0, (0.45 + coverage * 0.45) * freshnessFactor)
        return (wearableScore, reliability)
    }

    private func logDataReliability(_ logs: [WellnessLog]) -> Double {
        guard !logs.isEmpty else { return 0 }
        let componentCoverage = Double(logSignalComponentCount(in: logs)) / 4.0
        let sampleFactor = min(1.0, Double(logs.count) / 5.0)
        let newestSignalDays = logs.compactMap { daysAgo(from: $0.log_date) }.min() ?? 7
        let recencyFactor = max(0.6, 1.0 - min(newestSignalDays, 7) / 10.0)
        let reliability = (0.35 + componentCoverage * 0.35 + sampleFactor * 0.20) * recencyFactor
        return min(max(reliability, 0.35), 1.0)
    }

    private func logSignalComponentCount(in logs: [WellnessLog]) -> Int {
        var count = 0
        if logs.contains(where: { $0.sleep_duration_minutes != nil }) { count += 1 }
        if logs.contains(where: { $0.stress_level != nil }) { count += 1 }
        if logs.contains(where: { ($0.morning_energy ?? $0.energy_level) != nil }) { count += 1 }
        if logs.contains(where: { $0.exercise_duration_minutes != nil }) { count += 1 }
        return count
    }

    private func sleepStabilityScore(from log: WellnessLog) -> Double? {
        guard let minutes = log.sleep_duration_minutes else { return nil }
        let hours = Double(minutes) / 60.0
        var durationScore: Double
        if hours >= 7 && hours <= 9 {
            durationScore = 100
        } else if hours >= 6 && hours < 7 {
            durationScore = 75
        } else if hours > 9 && hours <= 10 {
            durationScore = 75
        } else if hours >= 5 && hours < 6 {
            durationScore = 50
        } else {
            durationScore = 25
        }

        if let quality = sleepQualityFactor(log.sleep_quality) {
            let qualityScore = quality * 100
            return durationScore * 0.8 + qualityScore * 0.2
        }
        return durationScore
    }

    private func energyStabilityScore(from log: WellnessLog) -> Double? {
        guard let energyValue = log.morning_energy ?? log.energy_level else { return nil }
        let raw = Double(energyValue)
        let normalized: Double = raw <= 5 ? (raw / 5.0) * 100.0 : (raw / 10.0) * 100.0
        return min(max(normalized, 0), 100)
    }

    private func exerciseStabilityScore(from log: WellnessLog) -> Double? {
        guard let minutes = log.exercise_duration_minutes else { return nil }
        if minutes >= 30 {
            return min(100, (Double(minutes) / 60.0) * 100)
        }
        return (Double(minutes) / 30.0) * 60
    }

    private func recencyWeightedAverage(
        _ samples: [(score: Double, daysAgo: Double)],
        halfLifeDays: Double = 3.0
    ) -> Double? {
        guard !samples.isEmpty else { return nil }
        let weighted = samples.reduce(into: (sum: 0.0, weight: 0.0)) { partial, sample in
            let days = max(0, sample.daysAgo)
            let weight = pow(0.5, days / max(halfLifeDays, 1))
            partial.sum += sample.score * weight
            partial.weight += weight
        }
        guard weighted.weight > 0 else { return nil }
        return weighted.sum / weighted.weight
    }

    private func daysAgo(from dateString: String, reference: Date = Date()) -> Double? {
        if let parsed = ISO8601DateFormatter().date(from: dateString) {
            return max(0, reference.timeIntervalSince(parsed) / 86_400.0)
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        if let parsed = formatter.date(from: String(dateString.prefix(10))) {
            return max(0, reference.timeIntervalSince(parsed) / 86_400.0)
        }
        return nil
    }

    private func clinicalScaleValue(_ key: String, from scores: [String: Int]) -> Int? {
        if let exact = scores[key] { return exact }
        let normalized = normalizedScaleKey(key)
        return scores.first(where: { normalizedScaleKey($0.key) == normalized })?.value
    }

    private func normalizedScaleKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func invertClinicalScale(_ value: Int, max upperBound: Int) -> Double? {
        guard upperBound > 0, value >= 0 else { return nil }
        let clamped = min(Swift.max(value, 0), upperBound)
        return (1.0 - (Double(clamped) / Double(upperBound))) * 100.0
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
