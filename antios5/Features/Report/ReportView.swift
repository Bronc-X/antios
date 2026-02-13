// ReportView.swift
// 报告页（数字孪生 + AI 身体分析）

import SwiftUI

struct ReportView: View {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @StateObject private var understandingViewModel = UnderstandingScoreViewModel()
    @Environment(\.screenMetrics) private var metrics
    @EnvironmentObject private var appSettings: AppSettings
    @State private var hasAutoTriggeredAnalysis = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        headerSection
                        statusBarCard
                        scienceJournalCard
                        digitalTwinCard
                        aiAnalysisCard
                        hrvSummaryCard
                        feedbackLoopCard
                        analysisInsightRow
                    }
                    .liquidGlassPageWidth()
                    .padding(.top, metrics.verticalPadding)
                    .padding(.bottom, metrics.bottomContentInset)
                }

                if dashboardViewModel.isLoading || understandingViewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle(tint: .liquidGlassAccent))
                }
            }
            .navigationBarHidden(true)
            .task {
                await loadData()
            }
            .refreshable {
                await refreshData()
            }
        }
    }

    private func loadData() async {
        async let dashboardTask: Void = dashboardViewModel.loadData()
        async let understandingTask: Void = understandingViewModel.load()

        await dashboardTask

        async let recommendationTask: Void = dashboardViewModel.loadDailyRecommendations(language: appSettings.language.apiCode)
        async let twinTask: Void = dashboardViewModel.loadDigitalTwin()

        await recommendationTask
        await twinTask
        await autoAnalyzeDigitalTwinIfNeeded()
        await understandingTask
    }

    private func refreshData() async {
        hasAutoTriggeredAnalysis = false
        async let refreshTask: Void = dashboardViewModel.refresh()
        async let understandingTask: Void = understandingViewModel.load()

        await refreshTask

        async let recommendationTask: Void = dashboardViewModel.loadDailyRecommendations(
            language: appSettings.language.apiCode,
            force: true
        )
        async let twinTask: Void = dashboardViewModel.loadDigitalTwin(force: true)

        await recommendationTask
        await twinTask
        await autoAnalyzeDigitalTwinIfNeeded()
        await understandingTask
    }

    private func autoAnalyzeDigitalTwinIfNeeded() async {
        let hasDashboard = dashboardViewModel.digitalTwinDashboard != nil
        let isStale = dashboardViewModel.digitalTwin?.isStale ?? false
        guard (!hasDashboard || isStale), !hasAutoTriggeredAnalysis else { return }

        hasAutoTriggeredAnalysis = true
        _ = await dashboardViewModel.analyzeDigitalTwin(forceRefresh: true)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("科学解释")
                .font(GlassTypography.display(28, weight: .bold))
                .foregroundColor(.textPrimary)
            Text("机制解释 · 证据来源 · 跟进策略")
                .font(GlassTypography.caption(13))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, metrics.isCompactHeight ? 8 : 16)
    }

    private var statusBarCard: some View {
        let scoreText = dashboardViewModel.overallScore.map(String.init) ?? "—"
        let completion = Int(loopCompletion * 100)

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("今日状态栏")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if dashboardViewModel.isOffline {
                        Label("本地模式", systemImage: "wifi.slash")
                            .font(.caption2)
                            .foregroundColor(.statusWarning)
                    }
                }

                HStack(spacing: 8) {
                    statusChip(title: "稳定度", value: scoreText)
                    statusChip(title: "连续", value: "\(calibrationStreakDays)天")
                    statusChip(title: "闭环节奏", value: "\(completion)%")
                }

                Text(statusFeedbackText)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private var scienceJournalCard: some View {
        let article = dashboardViewModel.featuredScienceArticle

        return LiquidGlassCard(style: .elevated, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .foregroundColor(.liquidGlassAccent)
                    Text("个性化科学解释")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                if dashboardViewModel.hasVerifiedScienceEvidence, let article {
                    Text(article.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)

                    Text(article.summary ?? "")
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    if let reason = article.whyRecommended, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("个性化关联：\(reason)")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }

                    if let action = article.actionableInsight, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("建议动作：\(action)")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }

                    Text("数据依据：\(dashboardViewModel.scienceEvidenceSnapshot)")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)

                    HStack(spacing: 10) {
                        if let score = article.matchPercentage {
                            Label("匹配 \(score)%", systemImage: "target")
                                .font(.caption2)
                                .foregroundColor(.liquidGlassAccent)
                        }

                        Text(article.sourceType ?? "个性化证据库")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                } else {
                    Text("科学解释仅在真实证据匹配完成后展示。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(dashboardViewModel.scienceEvidenceSnapshot)
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }

                HStack(spacing: 10) {
                    if let sourceUrl = article?.sourceUrl,
                       let url = URL(string: sourceUrl),
                       dashboardViewModel.hasVerifiedScienceEvidence {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("打开证据原文")
                            }
                            .font(.caption)
                            .foregroundColor(.liquidGlassAccent)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.surfaceGlass(for: .dark))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    NavigationLink(destination: ScienceFeedView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "newspaper.fill")
                            Text("进入科学期刊")
                        }
                        .font(.caption)
                        .foregroundColor(.liquidGlassAccent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.surfaceGlass(for: .dark))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    private var loopCompletion: Double {
        let total = Double(AntiAnxietyLoopStep.allCases.count)
        guard total > 0 else { return 0 }
        return Double(dashboardViewModel.antiAnxietyLoopStatus.completedSteps.count) / total
    }

    private var calibrationStreakDays: Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStrings = Set(dashboardViewModel.weeklyLogs.map { String($0.log_date.prefix(10)) })
        guard !dateStrings.isEmpty else { return 0 }

        var streak = 0
        var cursor = Calendar.current.startOfDay(for: Date())
        while true {
            let key = formatter.string(from: cursor)
            if dateStrings.contains(key) {
                streak += 1
                guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }
        return streak
    }

    private var statusFeedbackText: String {
        if let score = dashboardViewModel.overallScore {
            if score >= 80 {
                return "你当前状态稳定，保持现在的节奏就很好。"
            }
            if score >= 60 {
                return "你在持续改善，今天完成一个小动作就够了。"
            }
            return "你已经开始恢复，不用全做完，先做最容易的一步。"
        }
        return "先执行一个低负担动作，系统会继续给你个性化解释。"
    }

    private var digitalTwinCard: some View {
        NavigationLink(destination: DigitalTwinView().edgeSwipeBack()) {
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("数字孪生")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.textTertiary)
                    }
                    Text(dashboardViewModel.digitalTwinStatusMessage)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    if let status = dashboardViewModel.digitalTwinStatus {
                        Text("状态：\(status)")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var aiAnalysisCard: some View {
        NavigationLink(destination: BodyAnalysisView(analysis: dashboardViewModel.digitalTwinDashboard).edgeSwipeBack()) {
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI 身体分析")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Image(systemName: "sparkles")
                            .foregroundColor(.liquidGlassAccent)
                    }
                    let scoreText = understandingViewModel.score?.current.map { String(format: "%.0f", $0) } ?? "—"
                    Text("理解度：\(scoreText)")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    if let delta = understandingViewModel.latestDelta {
                        Text("近次变化：\(delta >= 0 ? "+" : "")\(String(format: "%.0f", delta))")
                            .font(.caption2)
                            .foregroundColor(delta >= 0 ? .statusSuccess : .statusWarning)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var hrvSummaryCard: some View {
        NavigationLink(destination: HRVDashboardView().edgeSwipeBack()) {
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apple Watch / HealthKit 证据")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Image(systemName: "applewatch")
                            .foregroundColor(.liquidGlassAccent)
                    }
                    Text(dashboardViewModel.scienceEvidenceSnapshot)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var feedbackLoopCard: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("行动反馈闭环")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("完成动作后，把体感变化告诉 Max（0-10），系统会在下一轮自动校准解释和建议。")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                NavigationLink(destination: MaxChatView().edgeSwipeBack()) {
                    Text("去和 Max 复盘")
                        .font(.caption)
                        .foregroundColor(.liquidGlassAccent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.surfaceGlass(for: .dark))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var analysisInsightRow: some View {
        let insights = dashboardViewModel.keyInsights

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("关键洞察")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                if insights.isEmpty {
                    Text("同步完成后会展示你的个性化趋势洞察。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                } else {
                    ForEach(insights.prefix(3), id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surfaceGlass(for: .dark))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatValue(_ value: Double?, suffix: String) -> String {
        guard let value, value > 0 else { return "—" }
        let display = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return L10n.runtime("\(display)\(suffix)")
    }
}

struct ReportMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.localized(title))
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(L10n.runtime(value))
                .font(.headline)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceGlass(for: .dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BodyAnalysisView: View {
    let analysis: DigitalTwinDashboardResponse?
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    header
                    analysisSummaryCard
                    baselineVitals
                    baselineAssessments
                    adaptivePlan
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("AI 身体分析")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("分析摘要")
                .font(.headline)
                .foregroundColor(.textPrimary)
            if let summary = analysis?.dashboardData.summaryStats {
                Text("\(L10n.localized("整体改善"))：\(L10n.runtime(summary.overallImprovement))")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Text("\(L10n.localized("一致性"))：\(L10n.runtime(summary.consistencyScore))")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            } else {
                Text("暂无趋势摘要，请先完成评估与校准。")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private var analysisSummaryCard: some View {
        let insights = bodyAnalysisInsights
        let actions = bodyAnalysisActions

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI 身体分析建议")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                if insights.isEmpty {
                    Text("当前数据不足以生成深入分析，请先完成评估与每日校准。")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                } else {
                    ForEach(insights, id: \.self) { item in
                        Text("• \(L10n.runtime(item))")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                }

                if !actions.isEmpty {
                    Divider().opacity(0.3)
                    Text("你可以这样做")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                    ForEach(actions, id: \.self) { action in
                        Text("• \(L10n.runtime(action))")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }

    private var bodyAnalysisInsights: [String] {
        var insights: [String] = []
        if let summary = analysis?.dashboardData.summaryStats {
            insights.append("\(L10n.runtime("整体改善趋势"))：\(L10n.runtime(summary.overallImprovement))，\(L10n.runtime("说明恢复方向正在建立。"))")
            insights.append("\(L10n.runtime("一致性"))：\(L10n.runtime(summary.consistencyScore))，\(L10n.runtime("规律性是当前最关键的增长点。"))")
        }

        let assessments = analysis?.dashboardData.baselineData.assessments ?? []
        for item in assessments {
            if item.name.contains("GAD") || item.name.contains("PHQ") || item.name.contains("ISI") {
                insights.append("\(L10n.runtime(item.name))：\(L10n.runtime(item.interpretation))，\(L10n.runtime("建议重点关注情绪与睡眠节律。"))")
                break
            }
        }

        return insights
    }

    private var bodyAnalysisActions: [String] {
        var actions: [String] = []
        if let summary = analysis?.dashboardData.summaryStats {
            if summary.daysToFirstResult > 0 {
                actions.append("连续记录与校准 7 天以上，提升模型准确度。")
            }
        }
        if actions.isEmpty {
            actions.append("每天固定 1 个可执行小动作（如 10 分钟慢呼吸或短时步行）。")
        }
        actions.append("睡前 1 小时减少屏幕刺激，稳定入睡时间。")
        return actions
    }

    private var baselineVitals: some View {
        let vitals = analysis?.dashboardData.baselineData.vitals ?? []
        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("生理指标")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                if vitals.isEmpty {
                    Text("暂无指标数据")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                } else {
                    ForEach(vitals.prefix(4)) { vital in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(.liquidGlassAccent)
                            Text("\(L10n.runtime(vital.name))：\(L10n.runtime(vital.value))")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var baselineAssessments: some View {
        let assessments = analysis?.dashboardData.baselineData.assessments ?? []
        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("基线量表")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                if assessments.isEmpty {
                    Text("暂无量表数据")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                } else {
                    ForEach(assessments.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.runtime(item.name))
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("\(L10n.runtime(item.value)) · \(L10n.runtime(item.interpretation))")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var adaptivePlan: some View {
        let plan = analysis?.adaptivePlan
        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI 计划建议")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                if let focus = plan?.dailyFocus.first {
                    Text("\(L10n.runtime("今日重点"))：\(L10n.runtime(focus.action))")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                } else {
                    Text("暂无今日重点")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }

                if let rec = plan?.sleepRecommendations.first {
                    Text("\(L10n.runtime("睡眠建议"))：\(L10n.runtime(rec.recommendation))")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                if let exercise = plan?.breathingExercises.first {
                    Text("\(L10n.localized("呼吸练习"))：\(L10n.runtime(exercise.name)) · \(L10n.runtime(exercise.duration))")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }

    private func formatValue(_ value: Int?, suffix: String) -> String {
        guard let value else { return "—" }
        return L10n.runtime("\(value)\(suffix)")
    }
}

struct HRVDashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HRV 指标看板")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("实时同步你的 HRV、心率、步数与睡眠")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("今日核心指标")
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            HStack(spacing: 12) {
                                ReportMetricView(title: "HRV", value: formatValue(viewModel.hardwareData?.hrv?.value, suffix: "ms"))
                                ReportMetricView(title: "静息心率", value: formatValue(viewModel.hardwareData?.resting_heart_rate?.value, suffix: "bpm"))
                            }
                            HStack(spacing: 12) {
                                ReportMetricView(title: "步数", value: formatValue(viewModel.hardwareData?.steps?.value, suffix: "步"))
                                ReportMetricView(title: "睡眠", value: formatValue(viewModel.averageSleepHours, suffix: "h"))
                            }
                        }
                    }

                if let source = viewModel.hardwareData?.hrv?.source {
                    Text("\(L10n.runtime("数据来源"))：\(L10n.runtime(source))")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.verticalPadding)
            .padding(.bottom, metrics.bottomContentInset)
        }
        }
        .navigationTitle("HRV 看板")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }

    private func formatValue(_ value: Double?, suffix: String) -> String {
        guard let value, value > 0 else { return "—" }
        let display = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return L10n.runtime("\(display)\(suffix)")
    }
}

struct WearableConnectView: View {
    @ObservedObject var viewModel: WearableConnectViewModel
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HealthKit 连接")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("同步 HRV、睡眠、心率等数据")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("连接状态")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Text(L10n.localized(viewModel.isAuthorized ? "已连接" : "未连接"))
                                    .font(.headline)
                                    .foregroundColor(viewModel.isAuthorized ? .statusSuccess : .textTertiary)
                            }

                            if let lastSync = viewModel.lastSync {
                                Text("上次同步：\(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }

                            if let error = viewModel.errorMessage {
                                Text(L10n.runtime(error))
                                    .font(.caption)
                                    .foregroundColor(.statusError)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    Task { await viewModel.connect() }
                                } label: {
                                    Text(L10n.localized(viewModel.isAuthorized ? "重新授权" : "授权 HealthKit"))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(LiquidGlassButtonStyle(isProminent: true))

                                Button {
                                    Task { await viewModel.syncNow() }
                                } label: {
                                    Text(L10n.localized(viewModel.isSyncing ? "同步中..." : "立即同步"))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
                                .disabled(viewModel.isSyncing)
                            }
                        }
                    }

                    LiquidGlassCard(style: .concave, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最新数据")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            HStack(spacing: 12) {
                                ReportMetricView(title: "HRV", value: formatValue(viewModel.hrv, suffix: "ms"))
                                ReportMetricView(title: "心率", value: formatValue(viewModel.restingHeartRate, suffix: "bpm"))
                            }
                            HStack(spacing: 12) {
                                ReportMetricView(title: "步数", value: formatValue(viewModel.steps, suffix: "步"))
                                ReportMetricView(title: "睡眠", value: formatValue(viewModel.sleepHours, suffix: "h"))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.verticalPadding)
                .padding(.bottom, metrics.bottomContentInset)
            }
        }
        .navigationTitle("穿戴设备")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refreshStatus()
        }
    }

    private func formatValue(_ value: Double?, suffix: String) -> String {
        guard let value, value > 0 else { return "—" }
        let display = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return L10n.runtime("\(display)\(suffix)")
    }
}

struct FeedbackLoopDetailView: View {
    @ObservedObject var viewModel: UnderstandingScoreViewModel
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AI 学习指标")
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            ScoreMetricRow(
                                title: "理解度评分",
                                value: viewModel.score?.current
                            )
                            ScoreMetricRow(
                                title: "预测准确率",
                                value: viewModel.score?.breakdown?.completionPredictionAccuracy
                            )
                            ScoreMetricRow(
                                title: "干预成功率",
                                value: viewModel.score?.breakdown?.replacementAcceptanceRate
                            )
                        }
                    }

                    LiquidGlassCard(style: .concave, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最近更新")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            if viewModel.history.isEmpty {
                                Text("暂无学习记录")
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            } else {
                                ForEach(viewModel.history.prefix(5)) { item in
                                    HStack {
                                        Text(item.date)
                                            .font(.caption2)
                                            .foregroundColor(.textTertiary)
                                        Spacer()
                                        Text("\(Int(item.score))%")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.verticalPadding)
                .padding(.bottom, metrics.bottomContentInset)
            }
        }
        .navigationTitle("学习反馈")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.score == nil {
                await viewModel.load()
            }
        }
    }
}

struct ScoreMetricRow: View {
    let title: String
    let value: Double?

    var body: some View {
        HStack {
            Text(L10n.localized(title))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(valueText)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 6)
    }

    private var valueText: String {
        guard let value else { return "—" }
        return "\(Int(value))%"
    }
}
