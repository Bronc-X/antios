// DashboardView.swift
// 反焦虑进展首页：弱约束节奏 + 个性化解释 + 行动跟进

import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    @State private var showLoopDetails = false
    @State private var showInsightSheet = false
    @State private var showGuideSheet = false
    @State private var showScienceFeedSheet = false
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        headerSection
                        heroSection
                        stateBarSection
                        rhythmSection
                        proactiveInquirySection
                        dailyCalibrationSection
                        scientificExplanationSection
                        actionClosureSection
                    }
                    .liquidGlassPageWidth()
                    .padding(.top, metrics.verticalPadding)
                    .padding(.bottom, metrics.bottomContentInset)
                }

                if viewModel.isLoading {
                    ProgressView()
                        .tint(.liquidGlassAccent)
                }
            }
            .navigationBarHidden(true)
            .task {
                await bootstrapLoop(force: false)
            }
            .refreshable {
                await bootstrapLoop(force: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .calibrationCompleted)) { _ in
                Task {
                    await bootstrapLoop(force: true)
                }
            }
            .alert(
                t("提示", "Notice"),
                isPresented: Binding(
                    get: { viewModel.error != nil },
                    set: { newValue in
                        if !newValue { viewModel.error = nil }
                    }
                )
            ) {
                Button(t("知道了", "Got it")) { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(isPresented: $showInsightSheet) {
                DashboardInsightSheet(
                    score: viewModel.overallScore,
                    progress: loopProgress,
                    streak: calibrationStreakDays,
                    feedback: positiveFeedbackText
                )
                .presentationDetents([.fraction(0.46), .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            }
            .sheet(isPresented: $showGuideSheet) {
                DashboardGuideSheet()
                    .presentationDetents([.fraction(0.42), .large])
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

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("进展", "Progress"))
                    .font(GlassTypography.cnLovi(30, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(t("弱约束节奏 · 个性化解释 · 行动跟进", "Weak constraint rhythm · Personalized explanation · Action follow-up"))
                    .font(GlassTypography.cnLovi(14, weight: .regular))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button {
                let haptic = UIImpactFeedbackGenerator(style: .soft)
                haptic.impactOccurred()
                showGuideSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.liquidGlassAccent)
                    .liquidGlassCircleBadge(padding: 8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroSection: some View {
        LiquidGlassCard(style: .elevated, padding: 20) {
            VStack(spacing: 24) {
                // 1. Semi-Circle Progress Gauge
                ZStack {
                    // Track
                    Circle()
                        .trim(from: 0.15, to: 0.85)
                        .stroke(Color.textSecondary.opacity(0.11), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(90))
                        .frame(width: 208, height: 208)
                    
                    // Score progress (0...100 mapped to 0...1)
                    Circle()
                        .trim(from: 0.15, to: 0.15 + (0.7 * scoreProgress)) // 0.7 is the span (0.85 - 0.15)
                        .stroke(
                            LinearGradient(
                                colors: [Color.bioGlow(for: colorScheme), Color.bioluminPink(for: colorScheme)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .rotationEffect(.degrees(90))
                        .frame(width: 208, height: 208)
                        .shadow(color: Color.bioluminPink(for: colorScheme).opacity(0.22), radius: 6)
                    
                    // Center Content (Glow Orb + Score)
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.bioluminPink(for: colorScheme).opacity(0.12),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 70
                                )
                            )
                            .frame(width: 148, height: 148)
                            .blur(radius: 8)
                        
                        VStack(spacing: 4) {
                            Text(viewModel.overallScore.map { "\($0)" } ?? "—")
                                .font(GlassTypography.loviTitle(56, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(t("稳定度 /100", "Stability /100"))
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(.top, 10)
                
                // 2. Greeting & Status
                VStack(spacing: 8) {
                    Text(viewModel.greeting)
                        .font(GlassTypography.cnLovi(22, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    Text(positiveFeedbackText)
                        .font(GlassTypography.cnLovi(15, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                    
                    Button {
                        let feedback = UIImpactFeedbackGenerator(style: .soft)
                        feedback.impactOccurred()
                        showInsightSheet = true
                    } label: {
                        Text(t("查看今日洞察", "View today's insights"))
                            .font(.caption.bold())
                            .foregroundColor(.liquidGlassAccent)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var stateBarSection: some View {
        let scoreText = viewModel.overallScore.map { "\($0)" } ?? "—"
        let completion = Int(loopProgress * 100)

        return LiquidGlassCard(style: .elevated, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("今日状态栏", "Today's status bar"))
                        .font(GlassTypography.cnLovi(19, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if viewModel.isOffline {
                        Label(t("本地模式", "Local mode"), systemImage: "wifi.slash")
                            .font(.caption2)
                            .foregroundColor(.statusWarning)
                    }
                }

                HStack(spacing: 8) {
                    statusChip(title: t("稳定度", "Stability"), value: scoreText)
                    statusChip(title: t("连续", "Streak"), value: t("\(calibrationStreakDays)天", "\(calibrationStreakDays) days"))
                    statusChip(title: t("节奏完成", "Rhythm completion"), value: "\(completion)%")
                }

                Text(positiveFeedbackText)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private var rhythmSection: some View {
        let status = viewModel.antiAnxietyLoopStatus

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("今日建议（可选）", "Today's tip (optional)"))
                        .font(GlassTypography.cnLovi(19, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("\(t("你可以优先：", "You can prioritize:")) \(r(status.currentStep.title))")
                        .font(.caption)
                        .foregroundColor(.liquidGlassAccent)
                }

                ProgressView(value: loopProgress)
                    .tint(.liquidGlassAccent)

                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLoopDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showLoopDetails ? t("收起进展详情", "Collapse progress details") : t("展开进展详情", "Expand progress details"))
                        Image(systemName: showLoopDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)

                if showLoopDetails {
                    HStack(spacing: 8) {
                        ForEach(AntiAnxietyLoopStep.allCases) { step in
                            let done = status.completedSteps.contains(step)
                            HStack(spacing: 4) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundColor(done ? .statusSuccess : .textTertiary)
                                Text(r(step.title))
                                    .font(.caption2)
                                    .foregroundColor(done ? .textPrimary : .textSecondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(Capsule())
                        }
                    }
                }

                if let hint = status.blockedReasons.first, !hint.isEmpty {
                    Text(hint)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var proactiveInquirySection: some View {
        if viewModel.isInquiryLoading {
            LiquidGlassCard(style: .standard, padding: 16) {
                HStack(spacing: 12) {
                    ProgressView().tint(.liquidGlassAccent)
                    Text(t("Max 正在整理下一条关注点…", "Max is preparing your next focus point…"))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        } else if let inquiry = viewModel.inquiry {
            LiquidGlassCard(style: .elevated, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: t("Max 关注点", "Max focus"), icon: "sparkles")

                    Text(r(inquiry.questionText))
                        .font(GlassTypography.cnLovi(16, weight: .medium))
                        .foregroundColor(.textPrimary)

                    if let feed = inquiry.feedContent {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("相关证据", "Related evidence"))
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                            Text(r(feed.title))
                                .font(GlassTypography.cnLovi(15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text(r(feed.source))
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(10)
                        .background(Color.surfaceGlass(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(spacing: 8) {
                        ForEach(resolvedInquiryOptions(inquiry), id: \.value) { option in
                            Button {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                Task {
                                    await viewModel.respondInquiry(option: option)
                                    await viewModel.loadDailyRecommendations(language: appSettings.language.apiCode, force: true)
                                }
                            } label: {
                                HStack {
                                    Text(r(option.label))
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.textTertiary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.surfaceGlass(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } else {
            LiquidGlassCard(style: .standard, padding: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.statusSuccess)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Max 关注点", "Max focus"))
                            .font(GlassTypography.cnLovi(18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(t("当前没有待回答问题，你可以直接看解释或执行动作。", "No pending questions. You can go straight to explanation or action."))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var dailyCalibrationSection: some View {
        NavigationLink(destination: DailyQuestionnaireView(log: viewModel.todayLog).edgeSwipeBack()) {
            LiquidGlassCard(style: .standard, padding: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3)
                        .foregroundColor(.liquidGlassWarm)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("今日校准（可选）", "Calibrate today (optional)"))
                            .font(GlassTypography.cnLovi(18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(viewModel.todayLog == nil
                             ? t("如果愿意，记录今天状态，建议会更贴合你。", "If you like, record today's status and recommendations will be more relevant.")
                             : t("今日已完成校准，做得很好。", "Calibration completed today, great job."))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Image(systemName: viewModel.todayLog == nil ? "chevron.right" : "checkmark.circle.fill")
                        .foregroundColor(viewModel.todayLog == nil ? .textTertiary : .statusSuccess)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var scientificExplanationSection: some View {
        let recommendation = viewModel.aiRecommendations.first
        let featured = viewModel.featuredScienceArticle
        let proactive = viewModel.proactiveCareBrief
        let mechanism = (featured?.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (recommendation?.summary ?? defaultMechanismExplanation)
            : (featured?.summary ?? defaultMechanismExplanation)
        let actionFromEvidence = (featured?.actionableInsight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionFromEvidence.isEmpty ? (recommendation?.action ?? defaultAction) : actionFromEvidence
        let personalizedReason = (featured?.whyRecommended ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return LiquidGlassCard(style: .elevated, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: t("科学解释", "Scientific explanation"), icon: "books.vertical.fill")

                if let proactive {
                    explanationRow(title: t("理解结论", "Conclusion"), value: r(proactive.understanding))
                    explanationRow(title: t("机制解释", "Mechanistic explanation"), value: r(proactive.mechanism))
                    explanationRow(title: t("可执行动作", "Action"), value: r(proactive.microAction))
                    explanationRow(title: t("跟进问题", "Follow-up question"), value: r(proactive.followUpQuestion))

                    if let evidenceTitle = proactive.evidenceTitle, !evidenceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        explanationRow(title: t("证据来源", "Source of evidence"), value: r(evidenceTitle))
                    }
                    if let confidence = proactive.confidence {
                        explanationRow(
                            title: t("解释置信度", "Confidence"),
                            value: "\(Int((min(max(confidence, 0), 1) * 100).rounded()))%"
                        )
                    }

                    HStack(spacing: 10) {
                        if let sourceUrl = proactive.evidenceURL,
                           let url = URL(string: sourceUrl),
                           !sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                    Text(t("打开证据原文", "Open source evidence"))
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
                            let haptic = UIImpactFeedbackGenerator(style: .soft)
                            haptic.impactOccurred()
                            showScienceFeedSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "newspaper.fill")
                                Text(t("进入个性化科学期刊", "Open personalized science journal"))
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
                } else if viewModel.hasVerifiedScienceEvidence, let featured {
                    explanationRow(title: t("理解结论", "Conclusion"), value: r(featured.title))
                    explanationRow(title: t("机制解释", "Mechanistic explanation"), value: r(mechanism))
                    explanationRow(title: t("个性化关联", "Personalized relevance"), value: personalizedReason.isEmpty ? t("已匹配你的真实健康数据", "Matched to your real health data") : r(personalizedReason))
                    explanationRow(title: t("证据来源", "Source of evidence"), value: r(featured.sourceType ?? t("个性化科学证据库", "Personalized evidence library")))
                    explanationRow(title: t("数据依据", "Data basis"), value: r(viewModel.scienceEvidenceSnapshot))
                    explanationRow(title: t("可执行动作", "Action"), value: r(action))
                    explanationRow(title: t("跟进问题", "Follow-up question"), value: t("执行后你的体感变化有多大（0-10）？", "After completing the action, how much did your body sensation change (0-10)?"))

                    HStack(spacing: 10) {
                        if let sourceUrl = featured.sourceUrl,
                           let url = URL(string: sourceUrl) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                    Text(t("打开证据原文", "Open source evidence"))
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
                            let haptic = UIImpactFeedbackGenerator(style: .soft)
                            haptic.impactOccurred()
                            showScienceFeedSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "newspaper.fill")
                                Text(t("进入个性化科学期刊", "Open personalized science journal"))
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
                } else {
                    Text(viewModel.hasSufficientHealthSignalsForScience
                         ? t("个性化科学解释暂未就绪", "Personalized scientific explanation is not ready yet")
                         : t("等待真实健康数据", "Waiting for real health data"))
                        .font(GlassTypography.cnLovi(18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(viewModel.hasSufficientHealthSignalsForScience
                         ? t("仅在云端证据可用且已匹配你的真实健康数据时展示。", "Shown only when cloud evidence is available and matched to your real health data.")
                         : t("请先完成今日校准或同步 Apple Watch/HealthKit，系统才会生成真实个性化解释。", "Please complete today's calibration or sync Apple Watch/HealthKit before personalized explanations can be generated."))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    explanationRow(title: t("当前数据状态", "Current data status"), value: r(viewModel.scienceEvidenceSnapshot))

                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .soft)
                        haptic.impactOccurred()
                        showScienceFeedSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text(t("查看并刷新科学期刊", "View and refresh scientific journals"))
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


    private var actionClosureSection: some View {
        let topActions = Array(viewModel.aiRecommendations.prefix(3))
        let fallbackActions = defaultActionFallbacks
        let proactiveAction = viewModel.proactiveCareBrief?.microAction
        let proactiveFollowUp = viewModel.proactiveCareBrief?.followUpQuestion

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: t("行动建议", "Action suggestions"), icon: "checkmark.seal")

                if topActions.isEmpty {
                    ForEach(Array(fallbackActions.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundColor(.liquidGlassAccent)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.liquidGlassAccent.opacity(0.18)))
                            Text(r(item))
                                .font(GlassTypography.cnLovi(15, weight: .regular))
                                .foregroundColor(.textSecondary)
                            Spacer()
                        }
                    }
                } else {
                    ForEach(topActions, id: \.id) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.liquidGlassAccent)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r(item.action))
                                    .font(GlassTypography.cnLovi(16, weight: .medium))
                                    .foregroundColor(.textPrimary)
                                Text(r(item.reason ?? item.summary))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                        }
                    }
                }

                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    let followUp = proactiveAction ?? topActions.first?.action ?? defaultAction
                    let prompt: String
                    if appSettings.language == .en {
                        let followUpQuestion = proactiveFollowUp ?? "What changed in your body sensation after this step (0-10)?"
                        prompt = "I just completed: \(followUp). Please give me the next best step and use this follow-up question: \(followUpQuestion)"
                    } else {
                        let followUpQuestion = proactiveFollowUp ?? "执行后你的体感变化有多大（0-10）？"
                        prompt = "我刚执行了：\(followUp)。请给我一个下一步，并用这个问题跟进：\(followUpQuestion)"
                    }
                    Task {
                        await SupabaseManager.shared.captureUserSignal(
                            domain: "dashboard",
                            action: "follow_up_requested",
                            summary: followUp,
                            metadata: [
                                "source": "action_closure_button",
                                "has_proactive_brief": viewModel.proactiveCareBrief != nil
                            ]
                        )
                    }
                    NotificationCenter.default.post(
                        name: .askMax,
                        object: nil,
                        userInfo: ["question": prompt]
                    )
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text(t("让 Max 继续跟进", "Let Max follow up"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var language: AppLanguage { appSettings.language }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.text(zh, en, language: language)
    }

    private func r(_ text: String) -> String {
        L10n.runtime(text, language: language)
    }

    private func bootstrapLoop(force: Bool) async {
        await viewModel.loadData(force: force)
        await viewModel.loadInquiry(language: appSettings.language.apiCode, force: force)
        await viewModel.loadDailyRecommendations(language: appSettings.language.apiCode, force: force)
    }

    private func resolvedInquiryOptions(_ inquiry: InquiryQuestion) -> [InquiryOption] {
        inquiry.options ?? [
            InquiryOption(label: t("是", "Yes"), value: "yes"),
            InquiryOption(label: t("否", "No"), value: "no")
        ]
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.liquidGlassAccent)
            Text(r(title))
                .font(GlassTypography.cnLovi(18, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
    }

    private func explanationRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r(title))
                .font(.caption)
                .foregroundColor(.textTertiary)
            Text(r(value))
                .font(GlassTypography.cnLovi(15, weight: .regular))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r(title))
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(r(value))
                .font(GlassTypography.cnLovi(17, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var loopProgress: Double {
        let total = Double(AntiAnxietyLoopStep.allCases.count)
        guard total > 0 else { return 0 }
        return Double(viewModel.antiAnxietyLoopStatus.completedSteps.count) / total
    }

    private var scoreProgress: Double {
        guard let score = viewModel.overallScore else { return 0 }
        return min(max(Double(score) / 100.0, 0), 1)
    }

    private var calibrationStreakDays: Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStrings = Set(viewModel.weeklyLogs.map { String($0.log_date.prefix(10)) })
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

    private var positiveFeedbackText: String {
        if let score = viewModel.overallScore {
            if score >= 80 {
                return t("你当前稳定度很好，继续维持节奏就可以。", "Your stability is strong today. Keep your current rhythm.")
            }
            if score >= 60 {
                return t("你已经在稳步改善，今天再完成一个小动作就足够。", "You're improving steadily. One small action today is enough.")
            }
            return t("状态在恢复中，先从最容易的一步开始，不需要全做完。", "You're recovering. Start with the easiest step, no need to finish everything.")
        }
        return t("先做一个低负担动作，系统会根据你的反馈继续优化建议。", "Start with a low-burden action. The system will keep optimizing based on your feedback.")
    }

    private var defaultMechanismExplanation: String {
        if let stress = viewModel.todayLog?.stress_level, stress >= 7 {
            return t("当前更像‘高唤醒-高警觉’状态，先降生理唤醒，再处理想法会更有效。", "Your current state looks like high arousal and vigilance. Reducing physiological arousal first is more effective.")
        }
        if viewModel.averageSleepHours > 0, viewModel.averageSleepHours < 6.5 {
            return t("睡眠偏短会放大威胁感知，白天小压力也会更容易引发焦虑波动。", "Short sleep amplifies threat perception, making daytime stress more likely to trigger anxiety swings.")
        }
        return t("焦虑是可调节的神经-行为回路反应，稳定节律和小步行动能降低波动。", "Anxiety is a regulatable neuro-behavioral loop. Stable rhythm and small actions can reduce fluctuations.")
    }

    private var defaultAction: String {
        if let stress = viewModel.todayLog?.stress_level, stress >= 7 {
            return t("先做 3 分钟慢呼吸（吸4秒-呼6秒），然后散步 8 分钟", "Do 3 minutes of slow breathing (inhale 4s, exhale 6s), then walk for 8 minutes.")
        }
        return t("先做 2 分钟呼吸 + 记录一个触发场景", "Do 2 minutes of breathing, then record one trigger scenario.")
    }

    private var defaultActionFallbacks: [String] {
        [
            defaultAction,
            t("把当前焦虑强度打分（0-10），并写下最主要触发点", "Rate your current anxiety (0-10) and write down the main trigger."),
            t("完成后告诉 Max：哪一步最有帮助", "After completion, tell Max which step helped the most.")
        ]
    }
}

private struct DashboardInsightSheet: View {
    let score: Int?
    let progress: Double
    let streak: Int
    let feedback: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var language: AppLanguage { L10n.currentLanguage() }
    private func t(_ zh: String, _ en: String) -> String { L10n.text(zh, en, language: language) }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(t("今日洞察", "Today's insights"))
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

                HStack(spacing: 8) {
                    sheetChip(title: t("稳定度", "Stability"), value: score.map(String.init) ?? "—")
                    sheetChip(title: t("跟进进度", "Progress"), value: "\(Int(progress * 100))%")
                    sheetChip(title: t("连续", "Streak"), value: t("\(streak)天", "\(streak) days"))
                }

                Text(feedback)
                    .font(GlassTypography.cnLovi(14, weight: .regular))
                    .foregroundColor(.textSecondary)

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                        NotificationCenter.default.post(name: .startCalibration, object: nil)
                    } label: {
                        Text(t("开始今日校准", "Start calibration today"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))

                    Button {
                        dismiss()
                        NotificationCenter.default.post(
                            name: .askMax,
                            object: nil,
                            userInfo: ["question": "请基于我今天的状态，给我一个最小可执行动作和一个复盘问题。"]
                        )
                    } label: {
                        Text(t("让 Max 解读", "Let Max interpret"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func sheetChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(GlassTypography.cnLovi(17, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct DashboardGuideSheet: View {
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
                    Text(t("进展页说明", "Progress page guide"))
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

                point(t("先看稳定度，再做一个动作：今天只需要完成最小一步。", "Check stability first, then do one action: today only needs the smallest step."))
                point(t("每个卡片都可以中断再回来，系统会记住你的节奏。", "Each card can be paused and resumed; the system remembers your rhythm."))
                point(t("完成动作后点“让 Max 继续跟进”，会自动给你复盘问题。", "After finishing, tap 'Let Max follow up' and you'll get a review question automatically."))

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.liquidGlassAccent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(GlassTypography.cnLovi(15, weight: .regular))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
