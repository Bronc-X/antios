// DashboardView.swift
// 反焦虑闭环首页：弱约束节奏 + 个性化解释 + 行动跟进

import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    @State private var showLoopDetails = false
    var body: some View {
        NavigationStack {
            ZStack {
                AbyssBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
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
                "提示",
                isPresented: Binding(
                    get: { viewModel.error != nil },
                    set: { newValue in
                        if !newValue { viewModel.error = nil }
                    }
                )
            ) {
                Button("知道了") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
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
                    
                    // Progress
                    Circle()
                        .trim(from: 0.15, to: 0.15 + (0.7 * loopProgress)) // 0.7 is the span (0.85 - 0.15)
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
                            Text(viewModel.overallScore.map { "\($0)" } ?? "0")
                                .font(.system(size: 56, weight: .bold, design: .serif))
                                .foregroundColor(.textPrimary)
                            Text("/100")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(.top, 10)
                
                // 2. Greeting & Status
                VStack(spacing: 8) {
                    Text(viewModel.greeting)
                        .font(.title3)
                        .foregroundColor(.textPrimary)
                    
                    Text(positiveFeedbackText)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                    
                    Button {
                        // Action for "See details"
                        withAnimation { showLoopDetails.toggle() }
                    } label: {
                        Text("查看今日洞察")
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
                    Text("今日状态栏")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if viewModel.isOffline {
                        Label("本地模式", systemImage: "wifi.slash")
                            .font(.caption2)
                            .foregroundColor(.statusWarning)
                    }
                }

                HStack(spacing: 8) {
                    statusChip(title: "稳定度", value: scoreText)
                    statusChip(title: "连续", value: "\(calibrationStreakDays)天")
                    statusChip(title: "节奏完成", value: "\(completion)%")
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
                    Text("今日建议（可选）")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("你可以优先：\(status.currentStep.title)")
                        .font(.caption)
                        .foregroundColor(.liquidGlassAccent)
                }

                ProgressView(value: loopProgress)
                    .tint(.liquidGlassAccent)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLoopDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showLoopDetails ? "收起闭环详情" : "展开闭环详情")
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
                                Text(step.title)
                                    .font(.caption2)
                                    .foregroundColor(done ? .textPrimary : .textSecondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.surfaceGlass(for: .dark))
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
                    Text("Max 正在整理下一条关注点…")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        } else if let inquiry = viewModel.inquiry {
            LiquidGlassCard(style: .elevated, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "Max 关注点", icon: "sparkles")

                    Text(inquiry.questionText)
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)

                    if let feed = inquiry.feedContent {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("相关证据")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                            Text(feed.title)
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text(feed.source)
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(10)
                        .background(Color.surfaceGlass(for: .dark))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(spacing: 8) {
                        ForEach(resolvedInquiryOptions(inquiry), id: \.value) { option in
                            Button {
                                Task {
                                    await viewModel.respondInquiry(option: option)
                                    await viewModel.loadDailyRecommendations(language: appSettings.language.apiCode, force: true)
                                }
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.textTertiary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.surfaceGlass(for: .dark))
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
                        Text("Max 关注点")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("当前没有待回答问题，你可以直接看解释或执行动作。")
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
                        Text("今日校准（可选）")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(viewModel.todayLog == nil ? "如果愿意，记录今天状态，建议会更贴合你。" : "今日已完成校准，做得很好。")
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
        let mechanism = (featured?.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (recommendation?.summary ?? defaultMechanismExplanation)
            : (featured?.summary ?? defaultMechanismExplanation)
        let actionFromEvidence = (featured?.actionableInsight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionFromEvidence.isEmpty ? (recommendation?.action ?? defaultAction) : actionFromEvidence
        let personalizedReason = (featured?.whyRecommended ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return LiquidGlassCard(style: .elevated, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "科学解释", icon: "books.vertical.fill")

                if viewModel.hasVerifiedScienceEvidence, let featured {
                    explanationRow(title: "理解结论", value: featured.title)
                    explanationRow(title: "机制解释", value: mechanism)
                    explanationRow(title: "个性化关联", value: personalizedReason.isEmpty ? "已匹配你的真实健康数据" : personalizedReason)
                    explanationRow(title: "证据来源", value: featured.sourceType ?? "个性化科学证据库")
                    explanationRow(title: "数据依据", value: viewModel.scienceEvidenceSnapshot)
                    explanationRow(title: "可执行动作", value: action)
                    explanationRow(title: "跟进问题", value: "执行后你的体感变化有多大（0-10）？")

                    HStack(spacing: 10) {
                        if let sourceUrl = featured.sourceUrl,
                           let url = URL(string: sourceUrl) {
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

                        NavigationLink(destination: ScienceFeedView().edgeSwipeBack()) {
                            HStack(spacing: 6) {
                                Image(systemName: "newspaper.fill")
                                Text("进入个性化科学期刊")
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
                } else {
                    Text(viewModel.hasSufficientHealthSignalsForScience ? "个性化科学解释暂未就绪" : "等待真实健康数据")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(viewModel.hasSufficientHealthSignalsForScience ? "仅在云端证据可用且已匹配你的真实健康数据时展示。" : "请先完成今日校准或同步 Apple Watch/HealthKit，系统才会生成真实个性化解释。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    explanationRow(title: "当前数据状态", value: viewModel.scienceEvidenceSnapshot)

                    NavigationLink(destination: ScienceFeedView().edgeSwipeBack()) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("查看并刷新科学期刊")
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


    private var actionClosureSection: some View {
        let topActions = Array(viewModel.aiRecommendations.prefix(3))
        let fallbackActions = defaultActionFallbacks

        return LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "行动建议", icon: "checkmark.seal")

                if topActions.isEmpty {
                    ForEach(Array(fallbackActions.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundColor(.liquidGlassAccent)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.liquidGlassAccent.opacity(0.18)))
                            Text(item)
                                .font(.subheadline)
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
                                Text(item.action)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                Text(item.reason ?? item.summary)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                        }
                    }
                }

                Button {
                    let followUp = topActions.first?.action ?? defaultAction
                    NotificationCenter.default.post(
                        name: .askMax,
                        object: nil,
                        userInfo: ["question": "我刚执行了：\(followUp)。请给我一个下一步和一个复盘问题。"]
                    )
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("让 Max 继续跟进")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.surfaceGlass(for: .dark))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bootstrapLoop(force: Bool) async {
        async let dataTask: Void = viewModel.loadData(force: force)
        async let inquiryTask: Void = viewModel.loadInquiry(language: appSettings.language.apiCode, force: force)
        await dataTask
        await inquiryTask
        await viewModel.loadDailyRecommendations(language: appSettings.language.apiCode, force: force)
    }

    private func resolvedInquiryOptions(_ inquiry: InquiryQuestion) -> [InquiryOption] {
        inquiry.options ?? [
            InquiryOption(label: "是", value: "yes"),
            InquiryOption(label: "否", value: "no")
        ]
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.liquidGlassAccent)
            Text(title)
                .font(.headline)
                .foregroundColor(.textPrimary)
        }
    }

    private func explanationRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.surfaceGlass(for: .dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.headline)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.surfaceGlass(for: .dark))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var loopProgress: Double {
        let total = Double(AntiAnxietyLoopStep.allCases.count)
        guard total > 0 else { return 0 }
        return Double(viewModel.antiAnxietyLoopStatus.completedSteps.count) / total
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
                return "你当前稳定度很好，继续维持节奏就可以。"
            }
            if score >= 60 {
                return "你已经在稳步改善，今天再完成一个小动作就足够。"
            }
            return "状态在恢复中，先从最容易的一步开始，不需要全做完。"
        }
        return "先做一个低负担动作，系统会根据你的反馈继续优化建议。"
    }

    private var defaultMechanismExplanation: String {
        if let stress = viewModel.todayLog?.stress_level, stress >= 7 {
            return "当前更像‘高唤醒-高警觉’状态，先降生理唤醒，再处理想法会更有效。"
        }
        if viewModel.averageSleepHours > 0, viewModel.averageSleepHours < 6.5 {
            return "睡眠偏短会放大威胁感知，白天小压力也会更容易引发焦虑波动。"
        }
        return "焦虑是可调节的神经-行为回路反应，稳定节律和小步行动能降低波动。"
    }

    private var defaultAction: String {
        if let stress = viewModel.todayLog?.stress_level, stress >= 7 {
            return "先做 3 分钟慢呼吸（吸4秒-呼6秒），然后散步 8 分钟"
        }
        return "先做 2 分钟呼吸 + 记录一个触发场景"
    }

    private var defaultActionFallbacks: [String] {
        [
            defaultAction,
            "把当前焦虑强度打分（0-10），并写下最主要触发点",
            "完成后告诉 Max：哪一步最有帮助"
        ]
    }
}
