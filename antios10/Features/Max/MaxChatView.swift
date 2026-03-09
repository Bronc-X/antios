// MaxChatView.swift
// Max AI 对话视图 - 支持 P1 功能

import SwiftUI

struct MaxChatView: View {
    @StateObject private var viewModel = MaxChatViewModel()
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appSettings: AppSettings
    @State private var isHistoryOpen = false
    @State private var showChatGuide = false
    @State private var animateAura = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                immersiveBackground

                // Error Banner
                if let error = viewModel.error {
                    VStack {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error)
                                .font(.caption)
                            Spacer()
                            Button {
                                viewModel.error = nil
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.top, metrics.safeAreaInsets.top + 20)
                        Spacer()
                    }
                    .zIndex(100)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    chatHeader

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                                MaxAgentThreadSurface(
                                    surface: viewModel.agentSurface,
                                    language: appSettings.language,
                                    onCheckIn: {
                                        viewModel.pendingExecutionRequest = .checkIn
                                    },
                                    onExplainBody: {
                                        viewModel.explainLatestBodySignals()
                                    },
                                    onInquiryAction: {
                                        viewModel.openInquiryThread()
                                    },
                                    onPlanAction: {
                                        if viewModel.agentSurface.plan.hasActivePlan {
                                            viewModel.pendingExecutionRequest = .planReview
                                        } else {
                                            viewModel.sendPreparedPrompt(viewModel.agentSurface.plan.prompt)
                                        }
                                    },
                                    onOpenProactive: {
                                        viewModel.openProactiveBriefInChat()
                                    },
                                    onContinueProactive: {
                                        viewModel.continueFromProactiveBrief()
                                    },
                                    onEvidenceAction: {
                                        viewModel.openEvidenceDetail()
                                    },
                                    onActionReview: { outcome in
                                        viewModel.submitActionReview(outcome)
                                    },
                                    onRefresh: {
                                        Task {
                                            await viewModel.refreshAgentSurface(forceProactiveBrief: true)
                                        }
                                    }
                                )
                                .padding(.top, 8)

                                if viewModel.messages.isEmpty {
                                    ImmersiveStarterView(questions: viewModel.starterQuestions) { question in
                                        viewModel.inputText = question
                                        viewModel.sendMessage()
                                    }
                                    .padding(.top, metrics.isCompactHeight ? 12 : 24)
                                }

                                ForEach(viewModel.messages) { message in
                                    MessageBubble(message: message) { selectedPlan in
                                        viewModel.savePlan(selectedPlan)
                                    }
                                    .id(message.id)
                                }
                                if viewModel.isTyping { TypingIndicator(language: appSettings.language) }
                            }
                            .liquidGlassPageWidth(alignment: .leading)
                            .padding(.vertical, metrics.verticalPadding)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let lastMessage = viewModel.messages.last {
                                withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
                            }
                        }
                    }

                    InputBarV2(
                        text: $viewModel.inputText,
                        isFocused: $isInputFocused,
                        isTyping: viewModel.isTyping,
                        modelMode: viewModel.modelMode,
                        onOpenHistory: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isHistoryOpen = true
                            }
                        },
                        onSend: { viewModel.handleInputSubmission() },
                        onToggleMode: { viewModel.toggleModelMode() },
                        onStop: { viewModel.stopGeneration() }
                    )
                }

                if isHistoryOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isHistoryOpen = false
                            }
                        }
                }

                HistoryDrawer(
                    conversations: viewModel.conversations,
                    currentConversationId: viewModel.currentConversationId,
                    onSelect: { conversation in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isHistoryOpen = false
                        }
                        Task {
                            await viewModel.switchConversation(conversation.id)
                        }
                    },
                    onNew: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isHistoryOpen = false
                        }
                        viewModel.startNewConversation()
                    },
                    onDelete: { conversation in
                        Task {
                            _ = await viewModel.deleteConversation(conversation.id)
                        }
                    }
                )
                .frame(width: historyDrawerWidth)
                .offset(x: isHistoryOpen ? 0 : -historyDrawerWidth - 12)
                .shadow(color: Color.black.opacity(0.45), radius: 20, x: 8, y: 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isHistoryOpen)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showChatGuide) {
                MaxGuideSheet()
                    .presentationDetents([.fraction(0.42), .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
            }
            .sheet(item: $viewModel.pendingExecutionRequest) { sheet in
                switch sheet {
                case .checkIn:
                    MaxAgentCheckInSheet(language: appSettings.language) { result in
                        viewModel.continueFromCheckIn(result)
                    }
                    .presentationDetents([.medium, .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
                case .planReview:
                    MaxAgentPlanReviewSheet(language: appSettings.language) { planName, completedItems, remainingCount in
                        viewModel.continueFromPlanReview(
                            planName: planName,
                            completedItems: completedItems,
                            remainingCount: remainingCount
                        )
                    } onNeedNewPlan: {
                        viewModel.sendPreparedPrompt(viewModel.agentSurface.plan.prompt)
                    }
                    .presentationDetents([.large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
                case .breathing(let minutes):
                    BreathingSessionView(durationMinutes: minutes)
                        .presentationDetents([.large])
                        .liquidGlassSheetChrome(cornerRadius: 28)
                case .inquiry:
                    MaxAgentInquirySheet(
                        language: appSettings.language,
                        inquiry: viewModel.agentSurface.inquiry.question
                    ) { question, option in
                        viewModel.continueFromInquiry(question: question, selectedOption: option)
                    } onNeedQuestion: {
                        viewModel.requestFocusedInquiry()
                    }
                    .presentationDetents([.medium, .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
                case .evidence:
                    MaxAgentEvidenceSheet(
                        language: appSettings.language,
                        evidence: viewModel.agentSurface.evidence
                    ) {
                        viewModel.explainAgentEvidence()
                    }
                    .presentationDetents([.medium, .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .askMax)) { notification in
                viewModel.handleAskMaxNotification(userInfo: notification.userInfo ?? [:])
            }
            .onReceive(NotificationCenter.default.publisher(for: .startCalibration)) { _ in
                viewModel.pendingExecutionRequest = .checkIn
            }
            .onReceive(NotificationCenter.default.publisher(for: .startBreathing)) { notification in
                let duration = (notification.userInfo?["duration"] as? Int).flatMap { max(1, $0) } ?? 5
                viewModel.pendingExecutionRequest = .breathing(minutes: duration)
            }
            .simultaneousGesture(historyEdgeGesture)
            .onAppear {
                withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                    animateAura = true
                }
                Task {
                    await viewModel.refreshAgentSurface()
                }
            }
        }
    }

    private var immersiveBackground: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            Circle()
                .fill(Color.liquidGlassAccent.opacity(0.2))
                .frame(width: 260, height: 260)
                .blur(radius: 42)
                .offset(x: animateAura ? -130 : -70, y: animateAura ? -220 : -180)
                .scaleEffect(animateAura ? 1.08 : 0.92)

            Circle()
                .fill(Color.liquidGlassWarm.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 44)
                .offset(x: animateAura ? 120 : 70, y: animateAura ? -30 : 20)
                .scaleEffect(animateAura ? 0.96 : 1.08)
        }
    }

    private var chatHeader: some View {
        let sidePadding = metrics.horizontalPadding
        let sideSlotWidth: CGFloat = 44
        return LiquidGlassCard(style: .standard, padding: 12) {
            ZStack {
                HStack(spacing: 0) {
                    Button(action: handleBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .liquidGlassCircleBadge(padding: 8)
                    }
                    .frame(width: sideSlotWidth, alignment: .leading)
                    Spacer()
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .soft)
                        impact.impactOccurred()
                        showChatGuide = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.liquidGlassAccent)
                            .liquidGlassCircleBadge(padding: 8)
                    }
                    .frame(width: sideSlotWidth, alignment: .trailing)
                }

                VStack(spacing: 2) {
                    Text("Max")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(L10n.text("Agent surface", "Agent surface", language: appSettings.language))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: metrics.centerAxisOffset)
            }
        }
        .padding(.horizontal, sidePadding)
        .padding(.top, metrics.safeAreaInsets.top + 12)
        .padding(.bottom, 10)
    }

    private var historyDrawerWidth: CGFloat {
        min(metrics.safeWidth * 0.78, 320)
    }

    private var historyEdgeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { value in
                let isEdgeSwipe = value.startLocation.x < 28
                if isEdgeSwipe && value.translation.width > 60 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isHistoryOpen = true
                    }
                } else if isHistoryOpen && value.translation.width < -60 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isHistoryOpen = false
                    }
                }
            }
    }

    private func handleBack() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        if presentationMode.wrappedValue.isPresented {
            dismiss()
        } else {
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        }
    }
}

private struct MaxGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Max 对话说明")
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

                maxBullet("先描述“今天最明显的不适”，再让 Max 给一个最小动作。")
                maxBullet("动作执行后直接反馈体感变化（0-10），会触发下一轮优化。")
                maxBullet("如果只想快问快答，单条问题控制在 1 个目标。")

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func maxBullet(_ text: String) -> some View {
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

private struct MaxAgentThreadSurface: View {
    let surface: MaxAgentSurfaceModel
    let language: AppLanguage
    let onCheckIn: () -> Void
    let onExplainBody: () -> Void
    let onInquiryAction: () -> Void
    let onPlanAction: () -> Void
    let onOpenProactive: () -> Void
    let onContinueProactive: () -> Void
    let onEvidenceAction: () -> Void
    let onActionReview: (MaxActionReviewOutcome) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Max Agent", "Max Agent", language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.liquidGlassAccent)
                    Text(L10n.text("Max 会先看身体信号，再接主动关怀、check-in 和计划推进。", "Max reads body signals first, then moves into proactive care, check-in, and plan follow-up.", language: language))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            MaxAgentCard(
                icon: "waveform.path.ecg",
                title: surface.body.headline,
                detail: surface.body.detail,
                accent: .liquidGlassWarm
            ) {
                HStack(spacing: 10) {
                    MaxAgentButton(
                        title: L10n.text("做 check-in", "Run check-in", language: language),
                        systemImage: "slider.horizontal.3",
                        prominence: .primary,
                        action: onCheckIn
                    )
                    MaxAgentButton(
                        title: L10n.text("解读信号", "Explain signals", language: language),
                        systemImage: surface.body.hasSignals ? "sparkles" : "arrow.triangle.2.circlepath",
                        prominence: .secondary,
                        action: onExplainBody
                    )
                }
            }

            MaxAgentCard(
                icon: "bubble.left.and.exclamationmark.bubble.right",
                title: surface.inquiry.headline,
                detail: surface.inquiry.detail,
                accent: .liquidGlassAccent
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let evidenceTitle = surface.inquiry.evidenceTitle,
                       !evidenceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MaxAgentKeyValueRow(
                            title: L10n.text("关联线索", "Related clue", language: language),
                            value: evidenceTitle
                        )
                    }

                    MaxAgentButton(
                        title: surface.inquiry.primaryTitle,
                        systemImage: surface.inquiry.hasPendingInquiry ? "list.bullet.clipboard" : "plus.bubble",
                        prominence: .primary,
                        action: onInquiryAction
                    )
                }
            }

            MaxAgentCard(
                icon: "checklist.checked",
                title: surface.plan.headline,
                detail: surface.plan.detail,
                accent: .liquidGlassAccent
            ) {
                MaxAgentButton(
                    title: surface.plan.ctaTitle,
                    systemImage: surface.plan.hasActivePlan ? "checkmark.circle" : "plus.circle",
                    prominence: .primary,
                    action: onPlanAction
                )
            }

            MaxAgentCard(
                icon: "bolt.heart",
                title: surface.proactive.headline,
                detail: surface.proactive.detail,
                accent: .liquidGlassSecondary
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    MaxAgentKeyValueRow(
                        title: L10n.text("今日动作", "Today's action", language: language),
                        value: surface.proactive.microAction
                    )
                    MaxAgentKeyValueRow(
                        title: L10n.text("跟进问题", "Follow-up", language: language),
                        value: surface.proactive.followUpQuestion
                    )

                    HStack(spacing: 10) {
                        if let secondaryTitle = surface.proactive.secondaryTitle {
                            MaxAgentButton(
                                title: secondaryTitle,
                                systemImage: "text.bubble",
                                prominence: .secondary,
                                action: onOpenProactive
                            )
                        }
                        MaxAgentButton(
                            title: surface.proactive.primaryTitle,
                            systemImage: surface.proactive.hasBrief ? "checkmark.circle" : "sparkles",
                            prominence: .primary,
                            action: onContinueProactive
                        )
                    }

                    if surface.actionReview.hasAction {
                        MaxAgentActionReviewRow(
                            summary: surface.actionReview,
                            language: language,
                            onSelect: onActionReview
                        )
                    }
                }
            }

            MaxAgentCard(
                icon: "cross.case",
                title: surface.evidence.headline,
                detail: surface.evidence.detail,
                accent: .liquidGlassWarm
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let sourceTitle = surface.evidence.sourceTitle,
                       !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MaxAgentKeyValueRow(
                            title: L10n.text("证据来源", "Evidence source", language: language),
                            value: sourceTitle
                        )
                    }
                    if let confidenceText = surface.evidence.confidenceText {
                        MaxAgentKeyValueRow(
                            title: L10n.text("解释置信度", "Confidence", language: language),
                            value: confidenceText
                        )
                    }

                    MaxAgentButton(
                        title: surface.evidence.primaryTitle,
                        systemImage: surface.evidence.hasEvidence ? "doc.text.magnifyingglass" : "sparkles",
                        prominence: .primary,
                        action: onEvidenceAction
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surfaceGlass(for: .dark).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct MaxAgentActionReviewRow: View {
    let summary: MaxAgentActionReviewSummary
    let language: AppLanguage
    let onSelect: (MaxActionReviewOutcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MaxAgentKeyValueRow(
                title: L10n.text("动作反馈", "Action review", language: language),
                value: summary.actionLabel
            )

            HStack(spacing: 8) {
                MaxAgentChipButton(
                    title: summary.completedTitle,
                    systemImage: "checkmark.circle",
                    accent: .liquidGlassAccent
                ) {
                    onSelect(.completed)
                }
                MaxAgentChipButton(
                    title: summary.tooHardTitle,
                    systemImage: "tortoise",
                    accent: .liquidGlassWarm
                ) {
                    onSelect(.tooHard)
                }
                MaxAgentChipButton(
                    title: summary.skippedTitle,
                    systemImage: "arrowshape.turn.up.right",
                    accent: .liquidGlassSecondary
                ) {
                    onSelect(.skipped)
                }
            }
        }
    }
}

private struct MaxAgentKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MaxAgentChipButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MaxAgentCard<Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let detail: String
    let accent: Color
    let actions: Actions

    init(
        icon: String,
        title: String,
        detail: String,
        accent: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.accent = accent
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surfaceGlass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

private struct MaxAgentButton: View {
    @Environment(\.colorScheme) private var colorScheme
    enum Prominence {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let prominence: Prominence
    let action: () -> Void

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: prominence == .primary ? .medium : .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(prominence == .primary ? .white.opacity(0.96) : .textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        prominence == .primary
                            ? Color(hex: "#1E222A")
                            : Color.surfaceGlass(for: colorScheme)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                prominence == .primary
                                    ? Color.white.opacity(0.08)
                                    : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MaxAgentCheckInSheet: View {
    let language: AppLanguage
    let onContinueWithMax: (DailyCalibrationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CalibrationViewModel()
    @State private var sliderSelections: [String: Double] = [:]

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("每日 Check-in", "Daily Check-in", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("先让 Agent 收集最少必要信号，再继续追问。", "Let the agent collect the minimum needed signals before continuing the follow-up.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoading && viewModel.questions.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.liquidGlassAccent)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    content
                }
            }
            .padding(20)
        }
        .task {
            guard viewModel.questions.isEmpty else { return }
            await viewModel.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome, .questions:
            questionContent
        case .analyzing:
            VStack(alignment: .leading, spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.liquidGlassAccent)
                Text(L10n.text("正在整理这次 check-in，并同步到你的记忆里。", "Processing this check-in and syncing it into your memory.", language: language))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .result:
            if let result = viewModel.result {
                resultContent(result)
            }
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(viewModel.currentQuestionIndex + 1), total: Double(max(viewModel.questions.count, 1)))
                .tint(.liquidGlassAccent)

            if let question = viewModel.currentQuestion {
                Text(question.text)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.textPrimary)

                if question.type == .slider {
                    sliderBlock(question)
                } else {
                    optionButtons(question)
                }
            }
        }
    }

    private func optionButtons(_ question: CalibrationQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(question.options ?? []) { option in
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    viewModel.answerQuestion(questionId: question.id, value: option.value)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sliderBlock(_ question: CalibrationQuestion) -> some View {
        let minValue = Double(question.min ?? 0)
        let maxValue = Double(question.max ?? 10)
        let value = Binding<Double>(
            get: {
                sliderSelections[question.id] ?? minValue
            },
            set: { newValue in
                sliderSelections[question.id] = newValue
            }
        )

        return VStack(alignment: .leading, spacing: 14) {
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            Slider(value: value, in: minValue...maxValue, step: 1)
                .tint(.liquidGlassAccent)

            Button {
                viewModel.answerQuestion(questionId: question.id, value: Int(value.wrappedValue))
            } label: {
                Text(L10n.text("继续", "Continue", language: language))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.liquidGlassAccent.opacity(0.22))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func resultContent(_ result: DailyCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("这次 check-in 已进入你的记忆层。", "This check-in is now part of your memory layer.", language: language))
                .font(.title3.weight(.semibold))
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(L10n.text("Daily Index", "Daily Index", language: language), "\(result.dailyIndex)")
                summaryRow("GAD2", "\(result.gad2Score)")
                summaryRow(L10n.text("压力", "Stress", language: language), "\(result.stressScore)")
                summaryRow(L10n.text("睡眠时长得分", "Sleep duration score", language: language), "\(result.sleepDurationScore)")
                summaryRow(L10n.text("睡眠质量得分", "Sleep quality score", language: language), "\(result.sleepQualityScore)")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )

            Button {
                onContinueWithMax(result)
                dismiss()
            } label: {
                Text(L10n.text("让 Max 基于这次 check-in 跟进", "Let Max continue from this check-in", language: language))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.liquidGlassAccent.opacity(0.22))
                    )
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text(L10n.text("稍后处理", "Maybe later", language: language))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
        }
    }
}

private struct MaxAgentPlanReviewSheet: View {
    let language: AppLanguage
    let onContinueWithMax: (_ planName: String, _ completedItems: [String], _ remainingCount: Int) -> Void
    let onNeedNewPlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PlansViewModel()
    @State private var planDrafts: [String: [PlanItemData]] = [:]
    @State private var savingPlanId: String?

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("计划进度", "Plan Progress", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("在 Max 里直接勾选完成项，然后让 Max 接着跟进。", "Check off completed items in Max, then let Max continue the follow-up.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoading && viewModel.plans.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.liquidGlassAccent)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if viewModel.activePlans.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("还没有进行中的计划。", "There is no active plan yet.", language: language))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("直接让 Max 基于身体状态生成今天的微计划，会比手动建表更符合 agent-first。", "Let Max generate today's micro-plan from your body state. That fits agent-first better than building a manual form.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)

                        Button {
                            onNeedNewPlan()
                            dismiss()
                        } label: {
                            Text(L10n.text("让 Max 生成今天微计划", "Ask Max for today's micro-plan", language: language))
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.liquidGlassAccent.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.activePlans) { plan in
                                planReviewCard(plan)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            await viewModel.loadPlans()
            seedDrafts()
        }
    }

    private func planReviewCard(_ plan: PlanData) -> some View {
        let items = planDrafts[plan.id] ?? plan.items
        let completedCount = items.filter { $0.completed }.count
        let remainingCount = max(items.count - completedCount, 0)
        let progress = items.isEmpty ? 0 : Int((Double(completedCount) / Double(items.count)) * 100)

        return MaxAgentPlanDraftCard(
            language: language,
            planName: plan.name,
            items: items,
            completedCount: completedCount,
            progress: progress,
            isSaving: savingPlanId == plan.id,
            onToggleItem: { index in
                toggleItem(planId: plan.id, index: index)
            },
            onSave: {
                Task {
                    await save(plan: plan, items: items, remainingCount: remainingCount)
                }
            }
        )
    }

    private func seedDrafts() {
        for plan in viewModel.activePlans {
            if planDrafts[plan.id] == nil {
                planDrafts[plan.id] = plan.items
            }
        }
    }

    private func toggleItem(planId: String, index: Int) {
        guard var draft = planDrafts[planId], draft.indices.contains(index) else { return }
        draft[index].completed.toggle()
        planDrafts[planId] = draft
    }

    private func save(plan: PlanData, items: [PlanItemData], remainingCount: Int) async {
        savingPlanId = plan.id
        let completedCount = items.filter { $0.completed }.count
        let status: PlanCompletionStatus
        if completedCount == 0 {
            status = .skipped
        } else if completedCount == items.count {
            status = .completed
        } else {
            status = .partial
        }

        await viewModel.updateItems(planId: plan.id, items: items, status: status)
        savingPlanId = nil

        guard viewModel.error == nil else { return }
        let completedItems = items.filter { $0.completed }.map { $0.text }
        onContinueWithMax(plan.name, completedItems, remainingCount)
        dismiss()
    }
}

private struct MaxAgentPlanDraftCard: View {
    let language: AppLanguage
    let planName: String
    let items: [PlanItemData]
    let completedCount: Int
    let progress: Int
    let isSaving: Bool
    let onToggleItem: (Int) -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planName)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(progressText)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Text("\(progress)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.liquidGlassAccent)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onToggleItem(index)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.completed ? .liquidGlassAccent : .textTertiary)
                                .font(.system(size: 18, weight: .semibold))
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(itemBackground)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onSave) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.textPrimary)
                    }
                    Text(L10n.text("保存并让 Max 继续", "Save and let Max continue", language: language))
                        .font(.headline)
                }
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.liquidGlassAccent.opacity(0.22))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var progressText: String {
        language == .en
            ? "Completed \(completedCount) / \(items.count)"
            : "已完成 \(completedCount) / \(items.count)"
    }

    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct MaxAgentInquirySheet: View {
    let language: AppLanguage
    let inquiry: InquiryQuestion?
    let onAnswered: (InquiryQuestion, InquiryOption) -> Void
    let onNeedQuestion: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("主动问询", "Guided Inquiry", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("先补最关键的一条信号，再让 Max 决定下一步动作。", "Fill the single highest-value signal first, then let Max decide the next action.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let inquiry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(runtime(inquiry.questionText))
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.textPrimary)

                            if let feed = inquiry.feedContent {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L10n.text("关联线索", "Related clue", language: language))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.liquidGlassAccent)
                                    Text(runtime(feed.title))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.textPrimary)
                                    Text(runtime(feed.source))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                    if let summary = feed.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(runtime(summary))
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    if let urlString = feed.url,
                                       let url = URL(string: urlString),
                                       !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Link(destination: url) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "link")
                                                Text(L10n.text("打开相关内容", "Open related content", language: language))
                                            }
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.liquidGlassAccent)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(sheetCardBackground)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(resolvedOptions(for: inquiry), id: \.value) { option in
                                    Button {
                                        submit(inquiry: inquiry, option: option)
                                    } label: {
                                        HStack {
                                            Text(runtime(option.label))
                                                .foregroundColor(.textPrimary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if isSubmitting {
                                                ProgressView()
                                                    .progressViewStyle(.circular)
                                                    .tint(.liquidGlassAccent)
                                            } else {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundColor(.textTertiary)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                        .background(sheetCardBackground)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSubmitting)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("当前没有待答问询。", "There is no pending inquiry right now.", language: language))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("如果你想继续把动作收窄，直接让 Max 生成一条新的聚焦问题。", "If you want to narrow the next action further, let Max generate one new focused question.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)

                        Button {
                            onNeedQuestion()
                            dismiss()
                        } label: {
                            Text(L10n.text("让 Max 继续追问", "Let Max ask the next question", language: language))
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.liquidGlassAccent.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(sheetCardBackground)
                    Spacer()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.statusWarning)
                }
            }
            .padding(20)
        }
    }

    private var sheetCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func resolvedOptions(for inquiry: InquiryQuestion) -> [InquiryOption] {
        inquiry.options ?? [
            InquiryOption(
                label: L10n.text("是", "Yes", language: language),
                value: "yes"
            ),
            InquiryOption(
                label: L10n.text("否", "No", language: language),
                value: "no"
            )
        ]
    }

    private func runtime(_ text: String) -> String {
        L10n.runtime(text, language: language)
    }

    private func submit(inquiry: InquiryQuestion, option: InquiryOption) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await SupabaseManager.shared.respondInquiry(inquiryId: inquiry.id, response: option.value)
                await MainActor.run {
                    onAnswered(inquiry, option)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

private struct MaxAgentEvidenceSheet: View {
    let language: AppLanguage
    let evidence: MaxAgentEvidenceSummary
    let onExplain: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("证据解释", "Evidence Explanation", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("先看机制和来源，再让 Max 用你的身体状态把它讲透。", "Review mechanism and sources first, then let Max explain it through your body state.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    evidenceRow(
                        title: L10n.text("机制解释", "Mechanism", language: language),
                        value: evidence.detail
                    )
                    if let sourceTitle = evidence.sourceTitle,
                       !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        evidenceRow(
                            title: L10n.text("证据来源", "Evidence source", language: language),
                            value: sourceTitle
                        )
                    }
                    if let confidenceText = evidence.confidenceText {
                        evidenceRow(
                            title: L10n.text("解释置信度", "Confidence", language: language),
                            value: confidenceText
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

                HStack(spacing: 10) {
                    if let urlString = evidence.sourceURL,
                       let url = URL(string: urlString),
                       !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text(L10n.text("打开证据原文", "Open source evidence", language: language))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(.liquidGlassAccent)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                    }

                    Button {
                        onExplain()
                        dismiss()
                    } label: {
                        Text(evidence.primaryTitle)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.liquidGlassAccent.opacity(0.22))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func evidenceRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Message Bubble (🆕 支持 Markdown)
struct MessageBubble: View {
    let message: ChatMessage
    var onPlanConfirm: ((PlanOption) -> Void)? = nil
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    
    // 检测是否包含 plan-options JSON
    private var planOptions: [PlanOption]? {
        guard message.role == .assistant else { return nil }
        return parsePlanOptions(from: message.content)
    }

    private var scientificSoothing: ScientificSoothingResponse? {
        guard message.role == .assistant else { return nil }
        return parseScientificSoothingResponse(from: message.content)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.surfaceGlass(for: colorScheme))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.liquidGlassAccent)
                }
            } else {
                Spacer()
            }
            
            // 消息气泡 - 根据内容类型选择渲染方式
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let options = planOptions, options.count >= 2 {
                    // 显示计划选择器
                    PlanSelectorView(options: options) { selectedPlan in
                        onPlanConfirm?(selectedPlan)
                    }
                } else if let soothing = scientificSoothing {
                    ScientificSoothingCard(response: soothing, language: appSettings.language)
                } else {
                    // 🆕 使用 Markdown 渲染 AI 消息
                    Group {
                        if message.role == .assistant {
                            MarkdownText(content: message.content)
                        } else {
                            Text(message.content)
                        }
                    }
                    .font(.body)
                    .foregroundColor(message.role == .user ? .white.opacity(0.95) : .textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                message.role == .user
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "#2B323A"), Color(hex: "#1E222A")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(Color.surfaceGlass(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        message.role == .user
                                            ? Color.white.opacity(0.08)
                                            : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    // 🆕 P2 长按复制
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                            let notification = UINotificationFeedbackGenerator()
                            notification.notificationOccurred(.success)
                        } label: {
                            Label(
                                L10n.text("复制消息", "Copy message", language: appSettings.language),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                }
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 4)
            }
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.liquidGlassSecondary)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parseScientificSoothingResponse(from content: String) -> ScientificSoothingResponse? {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let sectionAliases: [(key: String, aliases: [String])] = [
            ("understanding", ["理解结论", "理解結論", "Understanding Conclusion"]),
            ("mechanism", ["机制解释", "機制解釋", "Mechanism Explanation"]),
            ("evidence", ["证据来源", "證據來源", "Evidence Sources"]),
            ("actions", ["可执行动作", "可執行動作", "Executable Actions"]),
            ("followUp", ["跟进问题", "跟進問題", "Follow-up Question"])
        ]

        var buckets: [String: [String]] = Dictionary(uniqueKeysWithValues: sectionAliases.map { ($0.key, []) })
        var currentKey: String?

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let (key, remainder) = matchSectionLine(trimmed, aliases: sectionAliases) {
                currentKey = key
                if !remainder.isEmpty {
                    buckets[key, default: []].append(remainder)
                }
                continue
            }

            if let currentKey {
                buckets[currentKey, default: []].append(trimmed)
            }
        }

        let understanding = buckets["understanding", default: []].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let mechanism = buckets["mechanism", default: []].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let evidenceLines = buckets["evidence", default: []]
        let actionLines = buckets["actions", default: []]
        let followUp = buckets["followUp", default: []].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        let evidence = evidenceLines.compactMap { line -> ScientificEvidenceCitation? in
            let clean = stripListPrefix(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            return ScientificEvidenceCitation(
                source: clean,
                title: clean,
                year: nil,
                confidence: nil
            )
        }

        let actions = actionLines
            .map { stripListPrefix($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let response = ScientificSoothingResponse(
            understandingConclusion: understanding,
            mechanismExplanation: mechanism,
            evidenceSources: evidence,
            executableActions: actions,
            followUpQuestion: followUp
        )
        return response.isValid ? response : nil
    }

    private func matchSectionLine(
        _ line: String,
        aliases: [(key: String, aliases: [String])]
    ) -> (String, String)? {
        let normalizedLine = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for item in aliases {
            for alias in item.aliases {
                let candidates = [
                    alias,
                    "\(alias):",
                    "\(alias)："
                ]
                for candidate in candidates {
                    if normalizedLine.hasPrefix(candidate) {
                        let remainder = normalizedLine
                            .replacingOccurrences(of: candidate, with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return (item.key, remainder)
                    }
                }
            }
        }
        return nil
    }

    private func stripListPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
            return String(trimmed.dropFirst(2))
        }
        if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...])
        }
        return trimmed
    }
}

private struct ScientificSoothingCard: View {
    let response: ScientificSoothingResponse
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            soothingRow(title("理解结论", "Understanding"), response.understandingConclusion)
            soothingRow(title("机制解释", "Mechanism"), response.mechanismExplanation)
            soothingRow(title("证据来源", "Evidence"), response.evidenceSources.map { $0.title }.joined(separator: "；"))
            soothingRow(title("可执行动作", "Actions"), response.executableActions.joined(separator: "；"))
            soothingRow(title("跟进问题", "Follow-up"), response.followUpQuestion)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func soothingRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
        }
    }

    private func title(_ zh: String, _ en: String) -> String {
        L10n.text(zh, en, language: language)
    }
}

// MARK: - 🆕 P3 思考过程动画
struct TypingIndicator: View {
    let language: AppLanguage
    @State private var dotOffset = 0.0
    @State private var pulseScale = 1.0
    @State private var rotation = 0.0
    @State private var thinkingPhase = 0

    private var thinkingTexts: [String] {
        [
            L10n.text("正在理解你的焦虑场景...", "Understanding your anxiety context...", language: language),
            L10n.text("校准触发因素与身体信号...", "Calibrating triggers and body signals...", language: language),
            L10n.text("检索科学证据...", "Retrieving scientific evidence...", language: language),
            L10n.text("生成机制解释与行动方案...", "Generating mechanism explanation and action plan...", language: language),
            L10n.text("准备下一轮跟进问题...", "Preparing next follow-up question...", language: language)
        ]
    }
    
    private let timer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI 头像 - 带脉冲光晕和旋转
            ZStack {
                // 脉冲光圈
                Circle()
                    .fill(Color.liquidGlassAccent.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                
                Circle()
                    .fill(Color.liquidGlassAccent.opacity(0.25))
                    .frame(width: 40, height: 40)
                    .scaleEffect(pulseScale * 0.9)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.2),
                        value: pulseScale
                    )
                
                // 大脑图标 - 轻微旋转
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.liquidGlassAccent.opacity(0.5), lineWidth: 1.5))
                    .rotationEffect(.degrees(rotation))
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: rotation
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // 思考阶段文字
                Text(thinkingTexts[thinkingPhase % thinkingTexts.count])
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .animation(.easeInOut(duration: 0.3), value: thinkingPhase)
                
                // 三点跳动动画
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.liquidGlassAccent)
                            .frame(width: 8, height: 8)
                            .offset(y: dotOffset)
                            .animation(
                                .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15),
                                value: dotOffset
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.liquidGlassAccent.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            dotOffset = -6
            pulseScale = 1.2
            rotation = 5
        }
        .onReceive(timer) { _ in
            withAnimation {
                thinkingPhase += 1
            }
        }
    }
}

// MARK: - Immersive Starter View
struct ImmersiveStarterView: View {
    let questions: [String]
    let onSelect: (String) -> Void
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealCards = false

    private let icons = [
        "photo.on.rectangle",
        "video",
        "square.and.pencil",
        "book",
        "sparkles"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("你好")
                    .font(.system(size: metrics.isCompactWidth ? 20 : 22, weight: .semibold))
                    .foregroundColor(Color.textSecondary(for: colorScheme))
                Text("需要我为你做些什么？")
                    .font(.system(size: metrics.isCompactWidth ? 30 : 34, weight: .bold))
                    .foregroundColor(Color.textPrimary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(questions.prefix(5).enumerated()), id: \.offset) { index, question in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(question)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icons[index % icons.count])
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.textPrimary(for: colorScheme))
                            Text(question)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.textPrimary(for: colorScheme))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Capsule()
                                .fill(Color.surfaceGlass(for: colorScheme))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(revealCards ? 1 : 0)
                    .offset(y: revealCards ? 0 : 16)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.82).delay(Double(index) * 0.06),
                        value: revealCards
                    )
                }
            }
        }
        .padding(.vertical, 12)
        .onAppear {
            revealCards = true
        }
    }
}

// MARK: - History Drawer
struct HistoryDrawer: View {
    let conversations: [Conversation]
    let currentConversationId: String?
    let onSelect: (Conversation) -> Void
    let onNew: () -> Void
    let onDelete: (Conversation) -> Void
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            contentView

            Spacer()
        }
        .padding(.top, metrics.safeAreaInsets.top + 12)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(drawerBackground)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("历史记录")
                    .font(.headline)
                    .foregroundColor(Color.textPrimary(for: colorScheme))
                Text("最近上下文")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Color.textSecondary(for: colorScheme))
            }
            Spacer()
            Button(action: onNew) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.textPrimary(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .clipShape(Circle())
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if conversations.isEmpty {
            Text("还没有对话记录")
                .font(.subheadline)
                .foregroundColor(Color.textSecondary(for: colorScheme))
                .padding(.top, 12)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    Text(conversationDateLabel(conversation))
                        .font(.caption2)
                        .foregroundColor(Color.textTertiary(for: colorScheme))
                }
                Spacer()
                if conversation.id == currentConversationId {
                    Circle()
                        .fill(Color.liquidGlassAccent)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(conversation.id == currentConversationId
                          ? Color.liquidGlassAccent.opacity(0.16)
                          : Color.surfaceGlass(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                conversation.id == currentConversationId
                                    ? Color.liquidGlassAccent.opacity(0.24)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(conversation)
            } label: {
                Label("删除对话", systemImage: "trash")
            }
        }
    }

    private var drawerBackground: some View {
        ZStack {
            AuroraBackground()
            Rectangle()
                .fill(Color.surfaceGlass(for: colorScheme).opacity(0.92))
        }
        .ignoresSafeArea()
    }

    private func conversationDateLabel(_ conversation: Conversation) -> String {
        guard let date = conversation.lastMessageDate else { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 🆕 Input Bar V3 (支持图片上传和语音输入)
struct InputBarV2: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isTyping: Bool
    let modelMode: ModelMode
    let onOpenHistory: () -> Void
    let onSend: () -> Void
    let onToggleMode: () -> Void
    let onStop: () -> Void
    var onImageSelected: ((UIImage) -> Void)? = nil
    var onVoiceInput: ((String) -> Void)? = nil
    
    @State private var showImagePicker = false
    @State private var showVoiceRecorder = false
    @State private var isRecording = false
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    
    private var controlSize: CGFloat { metrics.isCompactWidth ? 36 : 40 }
    private var iconSize: CGFloat { metrics.isCompactWidth ? 17 : 19 }
    private var sendSize: CGFloat { metrics.isCompactWidth ? 30 : 32 }
    private var fieldHorizontalPadding: CGFloat { metrics.isCompactWidth ? 14 : 16 }
    private var fieldVerticalPadding: CGFloat { metrics.isCompactHeight ? 13 : 15 }
    private var barCornerRadius: CGFloat { metrics.isCompactWidth ? 24 : 28 }
    private var barMaxWidth: CGFloat { max(300, min(metrics.safeWidth - 16, 620)) }

    var body: some View {
        let sidePadding = max(8, metrics.horizontalPadding - 10)
        return ViewThatFits(in: .horizontal) {
            barContainer(content: barRow(showMode: true), sidePadding: sidePadding)
            barContainer(content: barRow(showMode: false), sidePadding: sidePadding)
        }
        // 🆕 图片选择器 Sheet
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                onImageSelected?(image)
            }
        }
        // 🆕 语音录入 Sheet
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView { transcribedText in
                text = transcribedText
            }
        }
    }

    private func barContainer(content: some View, sidePadding: CGFloat) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: barMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(Color.surfaceGlass(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: barCornerRadius)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.18), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08), radius: 20, y: 8)
            .padding(.horizontal, sidePadding)
            .padding(.top, 10)
            .padding(.bottom, max(12, metrics.safeAreaInsets.bottom + 6))
    }

    @ViewBuilder
    private func barRow(showMode: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            historyButton
            plusButton
            inputField
            if showMode {
                modePill
            }
            micButton
        }
    }

    private var historyButton: some View {
        Button(action: {
            lightImpact()
            onOpenHistory()
        }) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: controlSize, height: controlSize)
                .background(Color.surfaceGlass(for: colorScheme))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    private var plusButton: some View {
        Button(action: {
            lightImpact()
            showImagePicker = true
        }) {
            Image(systemName: "plus")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: controlSize, height: controlSize)
                .background(Color.surfaceGlass(for: colorScheme))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .disabled(isTyping)
        .opacity(isTyping ? 0.5 : 1)
    }

    private var micButton: some View {
        Button(action: {
            lightImpact()
            showVoiceRecorder = true
        }) {
            Image(systemName: "mic.fill")
                .font(.system(size: iconSize))
                .foregroundColor(.textPrimary)
                .frame(width: controlSize, height: controlSize)
                .background(Color.surfaceGlass(for: colorScheme))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .disabled(isTyping)
        .opacity(isTyping ? 0.5 : 1)
    }

    private var modePill: some View {
        Button(action: {
            lightImpact()
            onToggleMode()
        }) {
            Text(modelMode == .think ? "Pro" : "Fast")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(modelMode == .think ? .white : Color.textSecondary(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(modelMode == .think ? Color(hex: "#1E222A") : Color.surfaceGlass(for: colorScheme))
                        .overlay(
                            Capsule()
                                .stroke(modelMode == .think ? Color.white.opacity(0.08) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .disabled(isTyping)
        .opacity(isTyping ? 0.5 : 1)
    }

    private var inputField: some View {
        HStack(spacing: 10) {
            TextField("和 Max 说说现在最明显的不适", text: $text)
                .focused(isFocused)
                .textFieldStyle(.plain)
                .foregroundColor(Color.textPrimary(for: colorScheme))
                .layoutPriority(1)

            if isTyping {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    onStop()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: sendSize))
                        .foregroundStyle(.red.opacity(0.9))
                        .shadow(color: .red.opacity(0.4), radius: 6)
                }
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { onSend() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: sendSize))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color(hex: "#1E222A"))
                        .shadow(color: Color.black.opacity(0.24), radius: 8)
                }
            }
        }
        .padding(.horizontal, fieldHorizontalPadding)
        .padding(.vertical, fieldVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: metrics.isCompactHeight ? 50 : 56)
    }

    private func lightImpact() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// MARK: - 🆕 图片选择器 (PHPickerViewController)
import PhotosUI

struct ImagePickerView: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.onImageSelected(image)
                    }
                }
            }
        }
    }
}

// MARK: - 🆕 语音录入视图
import Speech

struct VoiceRecorderView: View {
    let onTranscription: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    @State private var pulseScale = 1.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    // 录音指示器
                    ZStack {
                        // 脉冲环
                        if isRecording {
                            Circle()
                                .stroke(Color.liquidGlassAccent.opacity(0.3), lineWidth: 4)
                                .frame(width: 160, height: 160)
                                .scaleEffect(pulseScale)
                            
                            Circle()
                                .stroke(Color.liquidGlassAccent.opacity(0.5), lineWidth: 3)
                                .frame(width: 130, height: 130)
                                .scaleEffect(pulseScale * 0.9)
                        }
                        
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.8) : Color.liquidGlassAccent)
                            .frame(width: 100, height: 100)
                            .shadow(color: isRecording ? .red.opacity(0.5) : .liquidGlassAccent.opacity(0.5), radius: 20)
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    .onTapGesture {
                        toggleRecording()
                    }
                    
                    Text(isRecording ? "点击停止录音" : "点击开始录音")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    
                    // 转录结果
                    if !transcribedText.isEmpty {
                        Text(transcribedText)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // 确认按钮
                    if !transcribedText.isEmpty && !isRecording {
                        Button {
                            onTranscription(transcribedText)
                            dismiss()
                        } label: {
                            Text("使用此文本")
                                .font(.headline)
                                .foregroundColor(.bgPrimary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.liquidGlassAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("语音输入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        stopRecording()
                        dismiss()
                    }
                    .foregroundColor(.liquidGlassAccent)
                }
            }
            .onAppear {
                requestSpeechAuthorization()
            }
            .onDisappear {
                stopRecording()
            }
            .onChange(of: isRecording) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseScale = 1.3
                    }
                } else {
                    pulseScale = 1.0
                }
            }
        }
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            // 授权处理
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    transcribedText = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    stopRecording()
                }
            }
        } catch {
            print("❌ 语音录制失败: \(error)")
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isRecording = false
    }
}

// MARK: - Preview
struct MaxChatView_Previews: PreviewProvider {
    static var previews: some View {
        MaxChatView()
            .preferredColorScheme(.dark)
    }
}

// MARK: - MarkdownText 组件
/// Markdown 文本渲染 - 使用 iOS 原生 AttributedString
struct MarkdownText: View {
    let content: String
    
    var body: some View {
        if #available(iOS 15.0, *) {
            Text(attributedContent)
                .textSelection(.enabled)
        } else {
            Text(content)
        }
    }
    
    @available(iOS 15.0, *)
    private var attributedContent: AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            
            var attributed = try AttributedString(markdown: content, options: options)
            attributed.foregroundColor = .white
            
            for run in attributed.runs {
                if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                    attributed[run.range].foregroundColor = .white
                }
                if run.inlinePresentationIntent?.contains(.emphasized) == true {
                    attributed[run.range].foregroundColor = .white.opacity(0.95)
                }
                if run.inlinePresentationIntent?.contains(.code) == true {
                    attributed[run.range].foregroundColor = .white.opacity(0.9)
                    attributed[run.range].backgroundColor = .white.opacity(0.1)
                }
            }
            return attributed
        } catch {
            return AttributedString(content)
        }
    }
}

// MARK: - StarterQuestionsView 组件
/// 个性化起始问题卡片视图
struct StarterQuestionsView: View {
    let questions: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.liquidGlassAccent)
                Text("快速开始")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
            }
            .padding(.bottom, 4)
            
            ForEach(questions.prefix(4), id: \.self) { question in
                StarterQuestionCard(question: question) {
                    onSelect(question)
                }
            }
        }
        .padding(.vertical, 16)
    }
}

/// 单个问题卡片
struct StarterQuestionCard: View {
    let question: String
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTap()
        }) {
            HStack {
                Text(question)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// 按压缩放按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
