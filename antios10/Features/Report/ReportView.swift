// ReportView.swift
// 报告页（数字孪生 + AI 身体分析）

import SwiftUI

struct ReportView: View {
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @StateObject private var understandingViewModel = UnderstandingScoreViewModel()
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings
    @State private var hasAutoTriggeredAnalysis = false
    @State private var showMethodSheet = false
    @State private var showScienceFeedSheet = false

    private var language: AppLanguage { appSettings.language }
    private func t(_ zh: String, _ en: String) -> String { L10n.text(zh, en, language: language) }
    private func r(_ value: String) -> String { L10n.runtime(value, language: language) }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        headerSection
                        heroInsightCard
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
            .sheet(isPresented: $showMethodSheet) {
                ReportMethodSheet(hasEvidence: dashboardViewModel.hasVerifiedScienceEvidence)
                    .presentationDetents([.fraction(0.45), .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
            }
            .sheet(isPresented: $showScienceFeedSheet) {
                NavigationStack {
                    ScienceFeedView()
                }
                .presentationDetents([.medium, .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            }
        }
    }

    private var heroInsightCard: some View {
        let evidenceReady = dashboardViewModel.hasVerifiedScienceEvidence
        let readinessText = evidenceReady
            ? t("今天的内容已经准备好", "Today's content is ready")
            : t("还在整理更贴近你的内容", "Preparing more relevant content")

        return LiquidGlassCard(style: .elevated, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("解释总览", "Explanation overview"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.liquidGlassAccent)
                        Text(t("先确认可信度，再决定要不要继续深入。", "Confirm confidence first, then decide whether to go deeper."))
                            .font(GlassTypography.cnLovi(17, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(statusFeedbackText)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(t("状态", "Status"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.textTertiary)
                        Text(readinessText)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(evidenceReady ? .statusSuccess : .statusWarning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background((evidenceReady ? Color.statusSuccess : Color.statusWarning).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    reportHeroMetric(
                        title: t("稳定度", "Stability"),
                        value: dashboardViewModel.overallScore.map(String.init) ?? "—",
                        accent: .liquidGlassAccent
                    )
                    reportHeroMetric(
                        title: t("执行节奏", "Execution rhythm"),
                        value: "\(Int(loopCompletion * 100))%",
                        accent: .liquidGlassFreshGreen
                    )
                    reportHeroMetric(
                        title: t("连续", "Streak"),
                        value: t("\(calibrationStreakDays)天", "\(calibrationStreakDays) days"),
                        accent: .liquidGlassWarm
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .soft)
                        haptic.impactOccurred()
                        showMethodSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles.rectangle.stack")
                            Text(t("查看解释方法", "View method"))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: false))

                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .soft)
                        haptic.impactOccurred()
                        showScienceFeedSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "newspaper.fill")
                            Text(t("进入科学期刊", "Open journals"))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                }
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("恢复分析", "Recovery analysis"))
                    .font(GlassTypography.cnLovi(30, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(t("原因说明 · 参考内容 · 下一步建议", "Reasons · references · next steps"))
                    .font(GlassTypography.cnLovi(14, weight: .regular))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .soft)
                haptic.impactOccurred()
                showMethodSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.liquidGlassAccent)
                    .liquidGlassCircleBadge(padding: 8)
            }
            .buttonStyle(.plain)
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
                    Text(t("今日状态栏", "Today's status bar"))
                        .font(GlassTypography.cnLovi(19, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if dashboardViewModel.isOffline {
                        Label(t("本地模式", "Local mode"), systemImage: "wifi.slash")
                            .font(.caption2)
                            .foregroundColor(.statusWarning)
                    }
                }

                HStack(spacing: 8) {
                    statusChip(title: t("稳定度", "Stability"), value: scoreText)
                    statusChip(title: t("连续", "Streak"), value: t("\(calibrationStreakDays)天", "\(calibrationStreakDays) days"))
                    statusChip(title: t("执行节奏", "Execution rhythm"), value: "\(completion)%")
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
                    Text(t("和你有关的内容", "Relevant for you"))
                        .font(GlassTypography.cnLovi(19, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                if dashboardViewModel.hasVerifiedScienceEvidence, let article {
                    Text(article.title)
                        .font(GlassTypography.cnLovi(16, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Text(article.summary ?? "")
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    if let reason = article.whyRecommended, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("\(t("个性化关联：", "Personalized relevance:"))\(r(reason))")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }

                    if let action = article.actionableInsight, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("\(t("建议动作：", "Suggested action:"))\(r(action))")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }

                    Text("\(t("参考内容：", "Reference:"))\(r(dashboardViewModel.scienceEvidenceSnapshot))")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)

                    HStack(spacing: 10) {
                        if let score = article.matchPercentage {
                            Label("\(t("匹配", "Match")) \(score)%", systemImage: "target")
                                .font(.caption2)
                                .foregroundColor(.liquidGlassAccent)
                        }

                        Text(r(article.sourceType ?? t("为你筛选的内容", "Picked for you")))
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                } else {
                    Text(t("有足够记录后，这里会显示更贴近你的内容。", "Once enough data is available, more relevant content will appear here."))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(r(dashboardViewModel.scienceEvidenceSnapshot))
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
                                Text(t("打开原文", "Open source"))
                            }
                            .font(.caption)
                            .foregroundColor(.liquidGlassAccent)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Button {
                        let feedback = UIImpactFeedbackGenerator(style: .soft)
                        feedback.impactOccurred()
                        showScienceFeedSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "newspaper.fill")
                            Text(t("看更多内容", "See more"))
                        }
                        .font(.caption)
                        .foregroundColor(.liquidGlassAccent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                            .background(Color.surfaceGlass(for: colorScheme))
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
                return t("你当前状态稳定，保持现在的节奏就很好。", "Your state is stable. Keep your current rhythm.")
            }
            if score >= 60 {
                return t("你在持续改善，今天完成一个小动作就够了。", "You're steadily improving. One small action today is enough.")
            }
            return t("你已经开始恢复，不用全做完，先做最容易的一步。", "Recovery has started. Start with the easiest step first.")
        }
        return t("先执行一个低负担动作，系统会继续给你个性化解释。", "Start with a low-burden action. The system will continue improving personalized explanations.")
    }

    private var digitalTwinCard: some View {
        NavigationLink(destination: DigitalTwinView().edgeSwipeBack()) {
            reportNavigationCard(
                title: t("身体状态", "Body status"),
                detail: dashboardViewModel.digitalTwinStatusMessage,
                systemImage: "waveform.path.ecg.rectangle",
                accent: .liquidGlassAccent,
                meta: dashboardViewModel.digitalTwinStatus.map { "\(t("状态", "Status")) · \(r($0))" }
            )
        }
        .buttonStyle(.plain)
    }

    private var aiAnalysisCard: some View {
        NavigationLink(destination: BodyAnalysisView(analysis: dashboardViewModel.digitalTwinDashboard).edgeSwipeBack()) {
            reportNavigationCard(
                title: t("身体分析", "Body analysis"),
                detail: t(
                    "结合最近状态和趋势，整理出更适合你的原因说明和动作建议。",
                    "Use recent state and trends to create reasons and next-step suggestions that fit you."
                ),
                systemImage: "brain.head.profile",
                accent: .liquidGlassWarm,
                meta: understandingViewModel.latestDelta.map {
                    "\(t("理解度", "Understanding")) · \(understandingViewModel.score?.current.map { String(format: "%.0f", $0) } ?? "—") · \(t("变化", "Change")) \($0 >= 0 ? "+" : "")\(String(format: "%.0f", $0))"
                } ?? "\(t("理解度", "Understanding")) · \(understandingViewModel.score?.current.map { String(format: "%.0f", $0) } ?? "—")"
            )
        }
        .buttonStyle(.plain)
    }

    private var hrvSummaryCard: some View {
        NavigationLink(destination: HRVDashboardView().edgeSwipeBack()) {
            reportNavigationCard(
                title: t("Apple Health 数据", "Apple Health data"),
                detail: r(dashboardViewModel.scienceEvidenceSnapshot),
                systemImage: "applewatch",
                accent: .liquidGlassSecondary,
                meta: t("设备记录", "Device records")
            )
        }
        .buttonStyle(.plain)
    }

    private var feedbackLoopCard: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.liquidGlassAccent)
                        .frame(width: 34, height: 34)
                        .background(Color.surfaceGlass(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(t("行动反馈", "Action feedback"))
                        .font(GlassTypography.cnLovi(18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
                Text(t("完成动作后，把体感变化告诉 Max（0-10），下一轮建议会更贴近你。", "After completing an action, tell Max how your body feels on a 0-10 scale. The next round will fit you better."))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .soft)
                    haptic.impactOccurred()
                    NotificationCenter.default.post(name: .openMaxChat, object: nil)
                } label: {
                    HStack(spacing: 6) {
                        Text(t("去和 Max 复盘", "Review with Max"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.liquidGlassAccent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var analysisInsightRow: some View {
        let insights = dashboardViewModel.keyInsights

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("关键洞察", "Key insights"))
                    .font(GlassTypography.cnLovi(18, weight: .semibold))
                    .foregroundColor(.textPrimary)

                if insights.isEmpty {
                    Text(t("同步完成后会展示你的个性化趋势洞察。", "Your personalized trend insights will appear after sync completes."))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                } else {
                    ForEach(insights.prefix(3), id: \.self) { item in
                        Text("• \(r(item))")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r(title))
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(r(value))
                .font(GlassTypography.cnLovi(17, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceGlass(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func reportHeroMetric(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.textTertiary)
            Text(value)
                .font(GlassTypography.cnLovi(15, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surfaceGlass(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.26), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reportNavigationCard(
        title: String,
        detail: String,
        systemImage: String,
        accent: Color,
        meta: String? = nil
    ) -> some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(GlassTypography.cnLovi(18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .padding(10)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .clipShape(Circle())
            }
        }
    }

    private func formatValue(_ value: Double?, suffix: String) -> String {
        guard let value, value > 0 else { return "—" }
        let display = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return L10n.runtime("\(display)\(suffix)")
    }
}

private struct ReportMethodSheet: View {
    let hasEvidence: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var language: AppLanguage { L10n.currentLanguage() }
    private func t(_ zh: String, _ en: String) -> String { L10n.text(zh, en, language: language) }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(t("解释方法", "How this explanation works"))
                        .font(GlassTypography.cnLovi(22, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(10)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                methodRow(title: t("① 为什么会这样", "① Why this"), text: t("根据你最近的睡眠、压力和节律变化，先说现在最可能的原因。", "Based on your recent sleep, stress, and rhythm, we first explain the most likely reason."))
                methodRow(title: t("② 我们参考了什么", "② What we looked at"), text: hasEvidence ? t("如果已经有足够记录，这里会告诉你参考了哪些内容，以及为什么和你有关。", "When enough records are available, we show what we looked at and why it relates to you.") : t("如果今天的信息还不够，就先给你更稳妥的建议。", "If today's information is still limited, we start with safer guidance first."))
                methodRow(title: t("③ 下一步怎么做", "③ What to do next"), text: t("每条建议都会配一个可执行动作和一个复盘问题，方便你继续往下走。", "Each suggestion includes one action and one review question so you can keep going easily."))

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func methodRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(GlassTypography.cnLovi(16, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(text)
                .font(GlassTypography.cnLovi(14, weight: .regular))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ReportMetricView: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.localized(title))
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(L10n.runtime(value))
                .font(GlassTypography.cnLovi(17, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceGlass(for: colorScheme))
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
                Text("暂无趋势摘要，先补几天记录后再来看会更清楚。")
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
                Text("身体分析建议")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                if insights.isEmpty {
                    Text("当前数据还不够，先多记录几天状态会更准确。")
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
                actions.append("连续记录 7 天以上，会更容易看出变化。")
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
                        Text("Apple Health 连接")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("同步心率、睡眠和活动等数据")
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
                                    Text(L10n.localized(viewModel.isAuthorized ? "重新授权" : "授权 Apple Health"))
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

// MARK: - Vibrant Mesh Background
struct MeshVibrantBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Base: Warm Peach / Orange
            Color(hex: "#FFD580").ignoresSafeArea()
            
            // Mesh 1: Violet Purple
            RadialGradient(
                colors: [Color(hex: "#8A2BE2").opacity(0.6), .clear],
                center: .topLeading,
                startRadius: 100,
                endRadius: 800
            )
            .offset(x: animate ? -100 : 0, y: animate ? -100 : 0)
            
            // Mesh 2: Emerald Green
            RadialGradient(
                colors: [Color(hex: "#50C878").opacity(0.5), .clear],
                center: .bottomTrailing,
                startRadius: 50,
                endRadius: 600
            )
            .offset(x: animate ? 100 : 0, y: animate ? 100 : 0)
            
            // Mesh 3: Soft Pink Overlay
            RadialGradient(
                colors: [Color(hex: "#FFB6C1").opacity(0.4), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
            .scaleEffect(animate ? 1.2 : 1.0)
            
            // Blur it all to mesh
            .blur(radius: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
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
